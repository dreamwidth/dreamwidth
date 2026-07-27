#!/usr/bin/perl
#
# DW::Task::DistributeInvites
#
# SQS worker for invite code distribution.
#
# Authors:
#     Pau Amma <pauamma@dreamwidth.org>
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::DistributeInvites;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::BusinessRules::InviteCodes;
use DW::InviteCodeRequests;
use DW::InviteCodes;
use LJ::Lang;
use LJ::Sendmail;
use LJ::Sysban;
use LJ::User;

use base 'DW::Task';

sub work {
    my ( $self, $handle ) = @_;

    my %arg = %{ $self->args->[0] };

    my ( $req_uid, $uckey, $ninv, $reason ) =
        map { delete $arg{$_} } qw( requester searchclass invites reason );

    if ( keys %arg ) {
        $log->error( "Unknown keys: " . join( ", ", keys %arg ) );
        return DW::Task::COMPLETED;
    }
    unless (defined $req_uid
        and defined $uckey
        and defined $ninv
        and defined $reason )
    {
        $log->error("Missing argument");
        return DW::Task::COMPLETED;
    }

    my $class_names = DW::BusinessRules::InviteCodes::user_classes();
    unless ( exists $class_names->{$uckey} ) {
        $log->error("Unknown user class: $uckey");
        return DW::Task::COMPLETED;
    }

    # Be optimistic and assume failure to load_userid = transient problem
    my $req_user = LJ::load_userid($req_uid);
    unless ($req_user) {
        $log->error("Unable to load requesting user");
        return DW::Task::FAILED;
    }

    my $max_nusers = DW::BusinessRules::InviteCodes::max_users($ninv);
    my $inv_uids   = DW::BusinessRules::InviteCodes::search_class( $uckey, $max_nusers );
    my $inv_nusers = scalar @$inv_uids;

    # Report email for requester
    my $req_lang    = $LJ::DEFAULT_LANG;
    my $req_usehtml = $req_user->prop('opt_htmlemail') eq 'Y';
    my $req_charset = 'utf-8';
    my %req_email   = (
        from     => $LJ::ACCOUNTS_EMAIL,
        fromname => $LJ::SITECOMPANY,
        to       => $req_user->email_raw,
        charset  => $req_charset,
        subject  => LJ::Lang::get_text( $req_lang, 'email.invitedist.req.subject', undef, {} ),
        body     => LJ::Lang::get_text(
            $req_lang,    # Gets extended later.
            'email.invitedist.req.header.plain', undef,
            { class => $class_names->{$uckey}, numinvites => $ninv }
        )
    );

    $req_email{html} = LJ::Lang::get_text(
        $req_lang,
        'email.invitedist.req.header.html',
        undef,
        {
            class      => $class_names->{$uckey},
            numinvites => $ninv,
            charset    => $req_charset
        }
    ) if $req_usehtml;

    my ( $reqemail_body, $reqemail_vars );

    # Figure out what to do, based on the number of invites and users
    if ( $max_nusers <= $inv_nusers ) {
        $reqemail_body = 'toomanyusers';
        $reqemail_vars = { maxusers => $max_nusers };
    }
    elsif ( $inv_nusers == 0 ) {
        $reqemail_body = 'nousers';
        $reqemail_vars = {};
    }
    else {
        my $adj_ninv      = DW::BusinessRules::InviteCodes::adj_invites( $ninv, $inv_nusers );
        my $num_sysbanned = 0;

        if ( $adj_ninv > 0 ) {

            # Here, we know we'll be generating invites, so get cracking.
            my $inv_peruser = int( $adj_ninv / $inv_nusers );
            $reqemail_vars->{peruser} = $inv_peruser;

            # FIXME: make magic number configurable
            for ( my $start = 0 ; $start < $inv_nusers ; $start += 1000 ) {
                my $end =
                    ( $start + 999 < $inv_nusers )
                    ? $start + 999
                    : $inv_nusers - 1;
                my $inv_uhash = LJ::load_userids( @{$inv_uids}[ $start .. $end ] );
                foreach my $inv_user ( values %$inv_uhash ) {

                    # skip sysbanned users; we may send a few less invites than we thought we could
                    if ( DW::InviteCodeRequests->invite_sysbanned( user => $inv_user ) ) {
                        $num_sysbanned++;
                        next;
                    }

                    my @ics = DW::InviteCodes->generate(
                        count  => $inv_peruser,
                        owner  => $inv_user,
                        reason => $reason
                    );
                    my $inv_lang      = $LJ::DEFAULT_LANG;
                    my $inv_usehtml   = $inv_user->prop('opt_htmlemail') eq 'Y';
                    my $inv_charset   = 'utf-8';
                    my $invemail_vars = {
                        username => $inv_user->user,
                        siteroot => $LJ::SITEROOT,
                        sitename => $LJ::SITENAMESHORT,
                        reason   => $reason,
                        number   => $inv_peruser,
                        codes    => join( "\n", @ics )
                    };

                    my %inv_email = (
                        from     => $LJ::ACCOUNTS_EMAIL,
                        fromname => $LJ::SITECOMPANY,
                        to       => $inv_user->email_raw,
                        charset  => $inv_charset,
                        subject  => LJ::Lang::get_text(
                            $inv_lang, 'email.invitedist.inv.subject',
                            undef, {}
                        ),
                        body => LJ::Lang::get_text(
                            $inv_lang, 'email.invitedist.inv.body.plain',
                            undef, $invemail_vars
                        )
                    );

                    $invemail_vars->{codes}   = join( "<br />\n", @ics );
                    $invemail_vars->{charset} = $inv_charset;
                    $inv_email{html} =
                        LJ::Lang::get_text( $inv_lang, 'email.invitedist.inv.body.html',
                        undef, $invemail_vars )
                        if $inv_usehtml;

                    LJ::send_mail( \%inv_email )
                        or $log->warn( "Can't email " . $inv_user->user );
                }
            }
        }

        # adjust the numbers to reflect how many we actually managed to distribute
        # accounting for sysbanned users (which we only know post-distribution)
        $inv_nusers -= $num_sysbanned;
        $adj_ninv   -= $num_sysbanned * $reqemail_vars->{peruser};

        if ( $adj_ninv == 0 ) {
            $reqemail_body = 'cantadjust';
            $reqemail_vars->{numusers} = $inv_nusers;
        }
        elsif ( $adj_ninv < $ninv ) {
            $reqemail_body               = 'adjustdown';
            $reqemail_vars->{actinvites} = $adj_ninv;
            $reqemail_vars->{remainder}  = $ninv - $adj_ninv;
            $reqemail_vars->{numusers}   = $inv_nusers;
        }
        elsif ( $adj_ninv > $ninv ) {
            $reqemail_body               = 'adjustup';
            $reqemail_vars->{actinvites} = $adj_ninv;
            $reqemail_vars->{additional} = $adj_ninv - $ninv;
            $reqemail_vars->{numusers}   = $inv_nusers;
        }
        else {
            $reqemail_body = 'keptsame';
            $reqemail_vars->{numusers} = $inv_nusers;
        }
    }

    $req_email{body} .=
        LJ::Lang::get_text( $req_lang, "email.invitedist.req.body.${reqemail_body}.plain",
        undef, $reqemail_vars );
    $req_email{body} .= LJ::Lang::get_text( $req_lang, 'email.invitedist.req.footer.plain',
        undef, { sitename => $LJ::SITENAMESHORT, siteroot => $LJ::SITEROOT } );

    if ($req_usehtml) {
        $req_email{html} .=
            LJ::Lang::get_text( $req_lang, "email.invitedist.req.body.${reqemail_body}.html",
            undef, $reqemail_vars );
        $req_email{html} .= LJ::Lang::get_text( $req_lang, 'email.invitedist.req.footer.html',
            undef, { sitename => $LJ::SITENAMESHORT, siteroot => $LJ::SITEROOT } );
    }

    LJ::send_mail( \%req_email )
        or $log->warn("Can't email requester");

    return DW::Task::COMPLETED;
}

1;
