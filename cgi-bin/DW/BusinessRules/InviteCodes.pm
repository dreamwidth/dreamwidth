#!/usr/bin/perl
#
# DW::BusinessRules::InviteCodes
#
# This module implements business rules for invite code distribution (both
# default/stub and site-specific through DW::BusinessRules and
# DW::BusinessRules::InviteCodes::*).
#
# Authors:
#      Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::BusinessRules::InviteCodes;
use strict;
use warnings;
use Carp       ();
use List::Util ();
use base 'DW::BusinessRules';
use LJ::Lang;

=head1 NAME

DW::BusinessRules::InviteCodes - business rules for invite code distribution

=head1 SYNOPSIS

  # Generate HTML to select a user class
  my $classes = DW::BusinessRules::InviteCodes::user_classes;
  my $html = LJ::html_select( {}, %$classes ); # Assumes unsorted is OK

  my $max_nusers = DW::BusinessRules::InviteCodes::max_users( $ninv );
  my $uids
      = DW::BusinessRules::InviteCodes::search_class( $class, $max_nusers );
  if (scalar( @$uids ) > $max_nusers) {
      # Sorry, too many users for the invites, even with the fudge factor
  }

  my $actual
      = DW::BusinessRules::InviteCodes::adj_invites( $ninv, scalar @$uids );
  foreach $uid (@$uids) {
      # Generate and email invite codes for $uid, or something. $actual is the
      # total number of invites to generate, so each user gets
      # $actual / scalar (@$uids);
  }

=head1 API

=head2 C<< DW::BusinessRules::InviteCodes::user_classes ( [ $lang ] ) >>

Returns a hashref of C<< { code => name } >> user classes. Names are translated
to $lang (defaults to LJ::Lang::get_effective_lang()). There are no restrictions
on codes (as long as user_classes and search_class agree on their meaning), and
classes can be anything that makes sense in the context of your policies
regarding invite codes.

Default implementation has only one class, lucky users, which draws users
randomly. (exor674 suggested "users who are on fire", but all implementations
of search_class I could think of have requirements that are probably unsuitable
to a production site.)

=cut

sub user_classes {
    my ($lang) = @_;
    $lang ||= LJ::Lang::get_effective_lang();
    return { lucky => LJ::Lang::get_text( $lang, 'invitecodes.userclass.lucky' ) };
}

=head2 C<< DW::BusinessRules::InviteCodes::max_users( $ninv ) >>

Returns a number of users known to be too large to accomodate $ninv invites,
even after applying any tolerance factor. This number may not be the exact
limit; the only guarantee is that any attempt to distribute $ninv invites (plus
any allowed adjustment) to that many users is bound to fail. This number should
be passed to search_class to keep it from wasting time by returning more users
than can possibly be accommodated.

The default implementation just returns $ninv + 1.

=cut

sub max_users {
    my ($ninv) = @_;

    return $ninv + 1;
}

=head2 C<< DW::BusinessRules::InviteCodes::search_class( $uckey, $max_nusers ) >>

Returns an arrayref of up to $max_nusers userids belonging to class $uckey.
$uckey must be one of the keys in the hashref returned by user_classes, and the
contents of each class is defined by search_class. (user_classes knows class
names, but not their contents.)

Important note: this can return $max_nusers userids, even though $max_nusers is
defined as "too many" by max_users(). This is so the caller can tell "too many"
from "just the number we wanted".

This function should be called from TheSchwartz only.

The default implementation just returns a bunch of random userids for personal
journals (not deleted or suspended) with validated email addresses. Note that
it uses a slow role for its database access. This is a good idea, and your
site-specific search_class should do the same.

=cut

sub search_class {
    my ( $uckey, $max_nusers ) = @_;
    Carp::croak("$uckey not a known user class") if $uckey ne 'lucky';

    my $dbslow = LJ::get_dbh('slow') or die "Can't get slow role";
    my ($last_uid) = $dbslow->selectrow_array("SELECT MAX(userid) FROM user");
    die $dbslow->errstr unless defined $last_uid;
    my $start_uid = int( rand($last_uid) );
    my @uids;

    # Not restricting on journaltype/status/statusvis here because:
    # 1- that may send us all the way to the end trying to get the limit
    # 2- we don't need or care to get that many users anyway
    # Instead, we prune the rows returned by the database (see below).
    my $sth =
        $dbslow->prepare( "SELECT userid, journaltype, status, statusvis "
            . "FROM user WHERE userid >= ? "
            . "ORDER BY userid ASC LIMIT ?" )
        or die $dbslow->errstr;
    $sth->execute( $start_uid, $max_nusers ) or die $sth->errstr;

    while ( my $row = $sth->fetchrow_hashref ) {
        push @uids, $row->{userid}
            if $row->{journaltype} eq 'P'
            && $row->{status} eq 'A'
            && $row->{statusvis} eq 'V';
        $max_nusers--;
    }

    return \@uids unless $max_nusers > 0;

    # Try again, this time going down
    $sth =
        $dbslow->prepare( "SELECT userid, journaltype, status, statusvis "
            . "FROM user WHERE userid < ? "
            . "ORDER BY userid DESC LIMIT ?" )
        or die $dbslow->errstr;
    $sth->execute( $start_uid, $max_nusers ) or die $sth->errstr;

    while ( my $row = $sth->fetchrow_hashref ) {
        push @uids, $row->{userid}
            if $row->{journaltype} eq 'P'
            && $row->{status} eq 'A'
            && $row->{statusvis} eq 'V';
        $max_nusers--;
    }

    return \@uids;
}

=head2 C<< DW::BusinessRules::InviteCodes::adj_invites( $ninv, $nusers ) >>

Returns an adjusted number of invites "close" to $ninv and that can be evenly
divided among $nusers recipients, or 0 if that adjustment is impossible or
would be too different from $ninv. Note that the returned value can be larger
than $inv if the site-specific business rules allow adjustement upward.

The default implementation returns the largest multiple of $ninv no larger than
$nusers.

=cut

sub adj_invites {
    my ( $ninv, $nusers ) = @_;

    return ( $ninv <= 0 || $nusers <= 0 ) ? 0 : ( $ninv - $ninv % $nusers );
}

DW::BusinessRules::install_overrides( __PACKAGE__,
    qw( user_classes max_users search_class adj_invites ) );
1;

=head1 BUGS

Bound to have some.

=head1 AUTHORS

Pau Amma <pauamma@dreamwidth.org>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.
