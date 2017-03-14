#!/usr/bin/perl
#
# DW::BusinessRules::InviteCodes::DWS
#
# This module implements business rules for invite code distribution that are
# specific to Dreamwidth Studios, LLC
#
# Authors:
#      Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2009-2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::BusinessRules::InviteCodes::DWS;
use strict;
use warnings;
use Carp ();
use base 'DW::BusinessRules::InviteCodes';

use DW::InviteCodes;
use LJ::User;
use DW::Pay;

=head1 NAME

DW::BusinessRules::InviteCodes::DWS - DWS-specific invite code business rules

=head1 DESCRIPTION

This module implements business rules for invite code distribution that are
specific to Dreamwidth Studios, LLC. Refer to DW::BusinessRules::InviteCodes
for more information and for the external API (user_classes, max_users,
search_class, and adj_invites).

=cut

# key => { search => \&search_fun [, search_arg => 'second argument' ] }
# key is also used for long cat name (invitecodes.userclass.*), and first
# argument is always max users to return.
my %user_classes = (
    basic_paid      => { search => \&_search_paystatus,
                         search_arg => [ typeid => 3 ] },
    premium_paid    => { search => \&_search_paystatus,
                         search_arg => [ typeid => 4 ] },
    permanent_paid  => { search => \&_search_paystatus,
                         search_arg => [ permanent => 1 ] },
    # Users active in the last 30 days
    active30d       => { search => \&_search_ctrk,
                         search_arg => 30 },
    # Users with no invites left
    noinvleft       => { search => \&_search_noinvleft }, # No search arg
    # Users with no invites left and 1 invitee paid/perm/active in last 30 days
    noinvleft_apinv => { search => \&_search_noinvleft_apinvitee,
                         search_arg => 30 },
);

sub user_classes {
    my ($lang) = @_;
    $lang ||= LJ::Lang::get_effective_lang();
    my %ucname;
    $ucname{$_}= LJ::Lang::get_text( $lang, "invitecodes.userclass.$_" )
        foreach keys %user_classes;
    return \%ucname;
}

# If there are fewer invites than qualifying users, invites get up to 1 per
# user, but only if invites are at least 3/4 of users. Hence, user limit is
# 4/3 of invites + 1.
sub max_users {
    my ($ninv) = @_;

    return int( $ninv + $ninv / 3 + 1 );
}

sub search_class {
    my ($uckey, $max_nusers) = @_;
    Carp::croak( "$uckey not a known user class" )
        unless exists $user_classes{$uckey};

    my $uclass = $user_classes{$uckey};
    return $uclass->{search}->( $uckey, $max_nusers, $uclass->{search_arg} );
}

# Search pay status
sub _search_paystatus {
    my ($uckey, $max_nusers, $search_arg) = @_;
    my $uids = DW::Pay::get_current_paid_userids( limit => $max_nusers,
                                                  @$search_arg );

    # TODO: Allow nonvalidated email addresses? We need to deal with users who
    # shouldn't be send email for some reason anyway (eg because they opted out
    # of mass mailings) by putting the notice in their inbox instead (or in
    # addition) or discarding it altogether, so might as well handle
    # nonvalidated addresses the same way. (Note that this applies to all
    # search functions, not just this one.)

    # Don't filter if too many, otherwise we lose that information
    return ($max_nusers <= scalar @$uids) ? $uids : _filter_pav( $uids );
}

# Search in "clustertrack2" (clustered) for recent activity
sub _search_ctrk {
    my ($uckey, $max_nusers, $days) = @_;
    my @uids;

    LJ::foreach_cluster( sub {
        return if $max_nusers <= @uids;

        my ($cid, $dbh) = @_;
        # Can't do a join here to weed out comms/unvalidated/not visible, since
        # the table with that info is elsecluster. So do separate filtering
        # pass using _filter_pav.
        my $sth = $dbh->prepare( "SELECT userid FROM clustertrack2 " .
                                 "WHERE timeactive >= UNIX_TIMESTAMP() - ? " .
                                 "LIMIT ?" )
            or die $dbh->errstr;
        my $cuids = $dbh->selectcol_arrayref( $sth, {}, $days * 86400,
                                              $max_nusers - @uids )
            or die $dbh->errstr;
        
        push @uids, @$cuids;
    } );

    # Don't filter if too many, otherwise we lose that information
    return ($max_nusers <= scalar @uids) ? \@uids : _filter_pav( \@uids );
}

# TODO: refactor into DW::InviteCodes
# Search "acctcode" (unclustered) for users with no invite left
sub _search_noinvleft {
    my ($uckey, $max_nusers) = @_;
    my $dbslow = LJ::get_dbh( 'slow' ) or die "Can't get slow role";

    # return all personal, active, visible journals... no need to use _filter_pav
    # later, when we can do it all on the user table to begin with.  this returns
    # all users that either have no invites OR
    my $uids = $dbslow->selectcol_arrayref(
        q{SELECT DISTINCT u.userid
          FROM user u
            LEFT JOIN acctcode a
              ON a.userid = u.userid AND a.rcptid = 0
          WHERE (u.journaltype = 'P' AND u.status = 'A' AND u.statusvis = 'V')
            AND a.userid IS NULL
        }
    );
    return $uids;
}

# TODO: refactor into DW::InviteCodes
# Search "acctcode" (unclustered) for users with no invite left, then restrict
# to those having at least one active or paid invitee
sub _search_noinvleft_apinvitee {
    my ($uckey, $max_nusers, $days) = @_;
    my $dbslow = LJ::get_dbh( 'slow' ) or die "Can't get slow role";

    # Second column will be all 0 here (and is unneeded anyway), but putting it
    # in HAVING and not SELECT is non-standard SQL.
    my $sth = $dbslow->prepare( "SELECT userid, min(rcptid) FROM acctcode " .
                                "GROUP BY userid HAVING min(rcptid) > 0 LIMIT ?" )
        or die $dbslow->errstr;
    # Keep only userid
    my $uids = $dbslow->selectcol_arrayref( $sth, { Columns => [1] }, $max_nusers )
        or die $dbslow->errstr;
    # Don't filter if too many, otherwise we lose that information
    return $uids if $max_nusers <= scalar @$uids;

    $uids = _filter_pav( $uids );
    my @filtered_uids;
    OWNER: foreach my $ouid (@$uids) {
        my @ics = DW::InviteCodes->by_owner( userid => $ouid );
        my @inv_uids;
        foreach my $code (@ics) {
            push @inv_uids, $code->recipient if $code->recipient;
        }
        my $inv_uhash = LJ::load_userids( @inv_uids );

        foreach my $iuser (values %$inv_uhash) {
            if ( defined( DW::Pay::get_current_account_status( $iuser ) )
                    || $iuser->get_timeactive >= time() - $days * 86400) {
                push @filtered_uids, $ouid;
                next OWNER;
            }
        }
    }
    return \@filtered_uids;
}

# From a list of userids, returns those for personal, visible journals with
# validated email addresses.
sub _filter_pav {
    my ($in_uids) = @_;
    my @out_uids;

    # TODO: make magic number configurable.
    # TODO: use splice() # perldoc -f splice
    for (my $start = 0; $start < @$in_uids; $start += 1000) {
        my $end = ($start + 999 <= $#$in_uids) ? $start + 999 : $#$in_uids;
        my $uhash = LJ::load_userids( @{$in_uids}[$start..$end] );
        while (my ($uid, $user) = each %$uhash) {
            push @out_uids, $uid
                if $user->is_person && $user->is_visible && $user->is_validated;
        }
    }

    return \@out_uids;
}

# Returns $ninv adjusted to next higher multiple of $nusers if remainder is at
# least 75% of $nusers, to next lower multiple instead.
sub adj_invites {
    my ($ninv, $nusers) = @_;

    return 0 if $ninv <= 0 || $nusers <= 0;

    my $remainder = $ninv % $nusers;

    return ( $remainder < 0.75 * $nusers )
        ? $ninv - $remainder
        : $ninv + $nusers - $remainder;
}

1;
