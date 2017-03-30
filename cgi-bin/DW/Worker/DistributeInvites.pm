#!/usr/bin/perl
#
# DW::Worker::DistributeInvites
#
# TheSchwartz worker module for invite code distribution. Called with:
# LJ::theschwartz()->insert('DW::Worker::DistributeInvites',
#     { requester => $remote->userid, searchclass => 'lucky',
#       invites => 42, reason => 'Because I wanna' } );
#
# Authors:
#      Pau Amma <pauamma@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

package DW::Worker::DistributeInvites;
use base 'TheSchwartz::Worker';
use DW::InviteCodes;
use DW::InviteCodeRequests;
use DW::BusinessRules::InviteCodes;
use LJ::User;
use LJ::Lang;
use LJ::Sysban;
use LJ::Sendmail;

sub schwartz_capabilities { return ('DW::Worker::DistributeInvites'); }

sub max_retries { 5 }

sub retry_delay {
    my ($class, $fails) = @_;

    return (10, 30, 60, 300, 600)[$fails];
}

sub keep_exit_status_for { 86400 } # 24 hours

# FIXME: tune value?
sub grab_for { 600 }

sub work {
    my ($class, $job) = @_;
    my %arg = %{$job->arg};

    my ($req_uid, $uckey, $ninv, $reason)
        = map { delete $arg{$_} } qw( requester searchclass invites reason );

    return $job->permanent_failure( "Unknown keys: " . join( ", ", keys %arg ))
        if keys %arg;
    return $job->permanent_failure( "Missing argument" )
        unless defined $req_uid and defined $uckey
               and defined $ninv and defined $reason;

    my $class_names = DW::BusinessRules::InviteCodes::user_classes();
    return $job->permanent_failure( "Unknown user class: $uckey" )
        unless exists $class_names->{$uckey};

    # Be optimistic and assume failure to load_userid = transient problem
    my $req_user = LJ::load_userid( $req_uid )
        or return $job->failed( "Unable to load requesting user" );

    my $max_nusers = DW::BusinessRules::InviteCodes::max_users( $ninv );
    my $inv_uids
        = DW::BusinessRules::InviteCodes::search_class( $uckey, $max_nusers );
    my $inv_nusers = scalar @$inv_uids;

    # Report email for requester
    my $req_lang = $LJ::DEFAULT_LANG;
    my $req_usehtml = $req_user->prop( 'opt_htmlemail' ) eq 'Y';
    my $req_charset = 'utf-8';
    my %req_email = (
        from => $LJ::ACCOUNTS_EMAIL,
        fromname => $LJ::SITECOMPANY,
        to => $req_user->email_raw,
        charset => $req_charset,
        subject => LJ::Lang::get_text( $req_lang,
            'email.invitedist.req.subject', undef, {} ),
        body => LJ::Lang::get_text( $req_lang, # Gets extended later.
            'email.invitedist.req.header.plain', undef,
            { class => $class_names->{$uckey}, numinvites => $ninv } ) );

    $req_email{html} = LJ::Lang::get_text( $req_lang,
            'email.invitedist.req.header.html', undef,
            { class => $class_names->{$uckey}, numinvites => $ninv,
              charset => $req_charset } )
        if $req_usehtml;

    my ($reqemail_body, $reqemail_vars);

    # Figure out what to do, based on the number of invites and users
    if ( $max_nusers <= $inv_nusers ) {
        $reqemail_body = 'toomanyusers';
        $reqemail_vars = { maxusers => $max_nusers };
    } elsif ( $inv_nusers == 0 ) {
        $reqemail_body = 'nousers';
        $reqemail_vars = {};
    } else {
        my $adj_ninv
            = DW::BusinessRules::InviteCodes::adj_invites( $ninv, $inv_nusers );
        my $num_sysbanned = 0;

        if ( $adj_ninv > 0 ) {
            # Here, we know we'll be generating invites, so get cracking.
            my $inv_peruser = int( $adj_ninv / $inv_nusers );
            $reqemail_vars->{peruser} = $inv_peruser;

            # FIXME: make magic number configurable
            for (my $start = 0; $start < $inv_nusers; $start += 1000) {
                my $end = ($start + 999 < $inv_nusers)
                    ? $start + 999
                    : $inv_nusers - 1;
                my $inv_uhash = LJ::load_userids( @{$inv_uids}[$start..$end] );
                foreach my $inv_user (values %$inv_uhash) {

                    # skip sysbanned users; we may send a few less invites than we thought we could
                    if ( DW::InviteCodeRequests->invite_sysbanned( user => $inv_user ) ) {
                        $num_sysbanned++;
                        next;
                    }

                    my @ics = DW::InviteCodes->generate( count => $inv_peruser,
                                                         owner => $inv_user,
                                                         reason => $reason );
                    my $inv_lang = $LJ::DEFAULT_LANG;
                    my $inv_usehtml = $inv_user->prop( 'opt_htmlemail' ) eq 'Y';
                    my $inv_charset = 'utf-8';
                    my $invemail_vars = {
                        username => $inv_user->user, siteroot => $LJ::SITEROOT,
                        sitename => $LJ::SITENAMESHORT, reason => $reason,
                        number => $inv_peruser, codes => join("\n", @ics) };

                    my %inv_email = (
                        from => $LJ::ACCOUNTS_EMAIL,
                        fromname => $LJ::SITECOMPANY,
                        to => $inv_user->email_raw,
                        charset => $inv_charset,
                        subject => LJ::Lang::get_text( $inv_lang,
                            'email.invitedist.inv.subject', undef, {} ),
                        body => LJ::Lang::get_text( $inv_lang,
                            'email.invitedist.inv.body.plain', undef,
                            $invemail_vars ) );

                    $invemail_vars->{codes} = join("<br />\n", @ics);
                    $invemail_vars->{charset} = $inv_charset;
                    $inv_email{html} = LJ::Lang::get_text( $inv_lang,
                            'email.invitedist.inv.body.html', undef,
                            $invemail_vars )
                        if $inv_usehtml;

                    LJ::send_mail( \%inv_email )
                        or $job->debug( "Can't email " . $inv_user->user );
                }
            }
        }

        # adjust the numbers to reflect how many we actually managed to distribute
        # accounting for sysbanned users (which we only know post-distribution)
        $inv_nusers -= $num_sysbanned;
        $adj_ninv -=  $num_sysbanned * $reqemail_vars->{peruser};

        if ( $adj_ninv == 0 ) {
            $reqemail_body = 'cantadjust';
            $reqemail_vars->{numusers} = $inv_nusers;
        } elsif ( $adj_ninv < $ninv ) {
            $reqemail_body = 'adjustdown';
            $reqemail_vars->{actinvites} = $adj_ninv;
            $reqemail_vars->{remainder} = $ninv - $adj_ninv;
            $reqemail_vars->{numusers} = $inv_nusers;
        } elsif ( $adj_ninv > $ninv ) {
            $reqemail_body = 'adjustup';
            $reqemail_vars->{actinvites} = $adj_ninv;
            $reqemail_vars->{additional} = $adj_ninv - $ninv;
            $reqemail_vars->{numusers} = $inv_nusers;
        } else {
            $reqemail_body = 'keptsame';
            $reqemail_vars->{numusers} = $inv_nusers;
        }
    }

    $req_email{body} .= LJ::Lang::get_text( $req_lang,
            "email.invitedist.req.body.${reqemail_body}.plain",
            undef, $reqemail_vars );
    $req_email{body} .= LJ::Lang::get_text( $req_lang,
            'email.invitedist.req.footer.plain', undef,
            { sitename => $LJ::SITENAMESHORT, siteroot => $LJ::SITEROOT } );

    if ($req_usehtml) {
        $req_email{html} .= LJ::Lang::get_text( $req_lang,
                "email.invitedist.req.body.${reqemail_body}.html",
                undef, $reqemail_vars );
        $req_email{html} .= LJ::Lang::get_text( $req_lang,
                'email.invitedist.req.footer.html', undef,
                { sitename => $LJ::SITENAMESHORT, siteroot => $LJ::SITEROOT } );
    }

    LJ::send_mail( \%req_email )
        or $job->debug( "Can't email requester" );

    $job->completed;
}

1;
