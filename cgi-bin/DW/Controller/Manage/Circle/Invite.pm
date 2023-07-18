#!/usr/bin/perl
#
# DW::Controller::Manage::Circle::Invite
#
# /manage/circle/invite
#
# Authors:
#      Cocoa <momijizukamori@gmail.com>
#
# Copyright (c) 2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Manage::Circle::Invite;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;

DW::Routing->register_string( "/manage/circle/invite", \&invite_handler, app => 1 );

sub invite_handler {
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;
    my $r    = DW::Request->get;
    my $POST = $r->post_args;

    my $remote = $rv->{remote};
    my $u      = $rv->{u};

    my @invitecodes;
    my $code;
    my $email_checkbox;
    my $body = '';
    my $create_link;

    if ($LJ::USE_ACCT_CODES) {
        @invitecodes = DW::InviteCodes->by_owner_unused( userid => $u->id );

        if ( $u->is_identity ) {
            return error_ml( '.error.openid', { sitename => $LJ::SITENAMESHORT } );
        }

        unless (@invitecodes) {
            $body = LJ::Lang::ml('/manage/circle/invite.tt.msg.noinvitecodes');
            $body .= " "
                . LJ::Lang::ml( '/manage/circle/invite.tt.msg.noinvitecodes.requestmore',
                { aopts => "href='$LJ::SITEROOT/invite'" } )
                if DW::BusinessRules::InviteCodeRequests::can_request( user => $u );
            return DW::Template->render_template( 'error.tt', { message => $body } );
        }

        $code = $POST->{code} || $invitecodes[0]->code;
        $create_link .= "&code=" . $code;

        # sort so that those which have been sent are last on the list
        @invitecodes = sort { ( $a->timesent || 0 ) <=> ( $b->timesent || 0 ) } @invitecodes;
    }

    my $code_sent;
    my $errors = DW::FormErrors->new;
    if ( $r->did_post ) {
        my $email = $POST->{'email'};
        if ($email) {
            my @errs;
            LJ::check_email( $email, \@errs, $POST, \$email_checkbox );
            $errors->add( "email", @errs ) if @errs;

            if ( $LJ::USER_EMAIL && $email =~ /$LJ::USER_DOMAIN$/ ) {
                $errors->add( "email", '.error.useralreadyhasaccount' );
            }

            unless ($LJ::USE_ACCT_CODES) {
                my $dbh = LJ::get_db_reader();
                my $ct  = $dbh->selectrow_array( "SELECT COUNT(*) FROM email WHERE email = ?",
                    undef, $email );

                if ( $ct > 0 ) {
                    my $findfriends_userhasaccount =
                        LJ::Hooks::run_hook("findfriends_invite_user_has_account");
                    if ($findfriends_userhasaccount) {
                        $errors->add( "email", $findfriends_userhasaccount );
                    }
                    else {
                        $errors->add( "email", '.error.useralreadyhasaccount' );
                    }
                }
            }

        }
        else {
            $errors->add( "email", '.error.noemail' );
        }

        if ( $POST->{'msg'} =~ /<(img|image)\s+src/i ) {
            $errors->add( "msg", '.error.noimagesallowed' );
        }

        foreach ( LJ::get_urls( $POST->{'msg'} ) ) {
            if ( $_ !~ m!^https?://([\w-]+\.)?$LJ::DOMAIN(/.*)?$!i ) {
                $errors->add(
                    "msg",
                    '.error.nooffsitelinksallowed2',
                    { sitename => $LJ::SITENAMESHORT, badurl => $_ }

                );
                last;
            }
        }

        unless ( $errors->exist ) {
            if ( $u->rate_log( 'invitefriend', 1 ) ) {

                $u->log_event(
                    'friend_invite_sent',
                    {
                        remote => $u,
                        extra  => $email,
                    }
                );

                if ($LJ::USE_ACCT_CODES) {

                    # mark an invite code as sent
                    my $invite_obj = DW::InviteCodes->new( code => $code );
                    $invite_obj->send_code( email => $email );

                    my $msg =
                        LJ::Lang::ml( '.success.code', { email => $email, invitecode => $code } );
                    $msg .= " " . LJ::Lang::ml('.success.invitemore')
                        if DW::InviteCodes->unused_count( userid => $u->id ) > 1;
                    $r->add_msg( $msg, $r->SUCCESS );
                    $code_sent = 1;

                }
                else {
                    $r->add_msg( LJ::Lang::ml( '.success', { email => $email } ), $r->SUCCESS );
                }

                # Blank email so the form is redisplayed for a new
                # recipient, but with the same message
                $email = '';

                # Over rate limit
            }
            else {
                $r->add_msg(
                    LJ::lang::ml(
                        '.error.overratelimit',
                        {
                            'sitename' => $LJ::SITENAMESHORT,
                            'aopts'    => "href='$LJ::SITEROOT/manage/circle/invite'"
                        }
                    ),
                    $r->ERROR
                );
            }
        }
    }
    my $msg = LJ::Lang::ml('/manage/circle/invite.tt.msg_custom');

    my $vars = {
        use_codes         => $LJ::USE_ACCT_CODES,
        errors            => $errors,
        invitecodes       => \@invitecodes,
        findfriends_intro => LJ::Hooks::run_hook("findfriends_invite_intro"),
        unusedinvites     => DW::InviteCodes->unused_count( userid => $u->id ),
        create_link       => $LJ::SITEROOT . "/create?from=$u->{user}",
        email_checkbox    => $email_checkbox,
        time_to_http      => \&LJ::time_to_http,
        u                 => $u,
        formdata          => { email => $POST->{email} || "", msg => $POST->{msg} || $msg },
    };

    return DW::Template->render_template( 'manage/circle/invite.tt', $vars );
}

1;
