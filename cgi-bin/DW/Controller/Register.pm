#!/usr/bin/perl
#
# DW::Controller::Register
#
# Used for confirming the email address associated with an account.
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and
# expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which made
# its code repository private in 2014. That license is archived here:
#
# https://github.com/apparentlymart/livejournal/blob/master/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2023 by Dreamwidth Studios, LLC.
#

package DW::Controller::Register;

use strict;

use DW::Routing;
use DW::Controller;
use DW::Template;
use DW::Captcha;

DW::Routing->register_regex( '^/confirm/(\w+\.\w+)', \&confirm_handler, app => 1 );

DW::Routing->register_string( '/register', \&main_handler, app => 1, no_cache => 1 );

sub confirm_handler {
    my ( $opts, $auth_string ) = @_;
    return DW::Request->get->redirect("/register?$auth_string");
}

sub main_handler {
    my ( $ok, $rv ) = controller( authas => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};
    my $foru;

    return error_ml( '/register.tt.error.identity_no_email',
        { aopts => "href='$LJ::SITEROOT/changeemail'" } )
        if $remote && $remote->is_identity && !$remote->email_raw;

    if ( my $foruser = $r->get_args->{foruser} ) {
        $foru = LJ::load_user($foruser);
        return error_ml('/register.tt.error.usernonexistent') unless $foru;
        return error_ml('/register.tt.error.noaccess')
            unless $remote && $remote->has_priv( "siteadmin", "users" );
        return error_ml('/register.tt.error.valid') if $foru->is_validated;
    }

    if ( $r->post_args->{'action:send'} || $foru ) {
        my $u = $foru ? $foru : $rv->{u};    # u is authas || remote
        return error_ml('error.invalidauth') unless $u;

        my $aa = LJ::register_authaction( $u->userid, "validateemail", $u->email_raw );

        LJ::send_mail(
            {
                'to'       => $u->email_raw,
                'bcc'      => $foru ? $remote->email_raw : undef,
                'from'     => $LJ::ADMIN_EMAIL,
                'fromname' => $LJ::SITENAME,
                'charset'  => 'utf-8',
                'subject' =>
                    LJ::Lang::ml( "/register.tt.email.subject", { sitename => $LJ::SITENAME } ),
                'body' => LJ::Lang::ml(
                    '/register.tt.email.body',
                    {
                        'sitename' => $LJ::SITENAME,
                        'siteroot' => $LJ::SITEROOT,
                        'email'    => $u->email_raw,
                        'username' => $u->display_name,
                        'conflink' => "$LJ::SITEROOT/confirm/$aa->{aaid}.$aa->{authcode}",
                    }
                ),
            }
        );

        return success_ml( '/register.tt.success.sent', { email => $u->email_raw } );
    }

    my $vars = { authas_form => $rv->{authas_form}, u => $rv->{u} };
    my $qs   = ( $r->post_args->{qs} || $r->query_string ) // '';

    if ( $qs =~ /^(\d+)[;\.](.+)$/ ) {
        my ( $aaid, $auth ) = ( $1, $2 );
        my $aa = LJ::is_valid_authaction( $aaid, $auth );

        return error_ml( '/register.tt.error.invalidcode',
            { aopts => "href='$LJ::SITEROOT/register'" } )
            unless $aa;

        my $u = LJ::load_userid( $aa->{userid} );
        return error_ml('/register.tt.error.usernotfound') unless $u;

        # verify their email hasn't subsequently changed
        return error_ml( '/register.tt.error.emailchanged',
            { aopts => "href='$LJ::SITEROOT/register'" } )
            unless $u->email_raw eq $aa->{arg1};

        $vars->{query_str} = $qs;

        # if the user is OpenID, prove that he or she is human
        if ( $u->is_identity ) {
            my $captcha = DW::Captcha->new( 'validate_openid', %{ $r->post_args || {} } );

            if ( $captcha->has_response ) {
                return error_ml("error.invalidform") unless $captcha->enabled;

                my $err_ref;
                return DW::Template->render_template( 'error.tt', { message => $err_ref } )
                    unless $captcha->validate( err_ref => \$err_ref );
            }
            else {
                $vars->{captcha} = $captcha;
                return DW::Template->render_template( 'register.tt', $vars );
            }
        }

        $u->update_self( { status => 'A' } );
        $u->update_email_alias;
        LJ::Hooks::run_hook( 'email_verified', $u );

        LJ::Hooks::run_hook(
            'post_email_change',
            {
                user     => $u,
                newemail => $aa->{arg1},
                suspend  => 1,
            }
        );

        return success_ml('/register.tt.success.trans') if $u->email_status eq "T";

        $vars->{u} = $u;
    }

    return DW::Template->render_template( 'register.tt', $vars );
}

1;
