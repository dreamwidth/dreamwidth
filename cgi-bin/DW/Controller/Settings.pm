#!/usr/bin/perl
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and expanded
# by Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Mark Smith <mark@dreamwidth.org>
#      Jen Griffin <kareila@livejournal.com> (lostinfo conversion)
#
# Copyright (c) 2014-2020 by Dreamwidth Studios, LLC.

package DW::Controller::Settings;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Imager::QRCode;

use DW::Auth::TOTP;
use DW::Controller;
use DW::Routing;
use DW::Template;
use DW::FormErrors;
use DW::Captcha;

=head1 NAME

DW::Controller::Settings - Controller for settings/settings-related pages

=cut

DW::Routing->register_string( "/accountstatus",    \&account_status_handler,   app    => 1 );
DW::Routing->register_string( "/changepassword",   \&changepassword_handler,   app    => 1, );
DW::Routing->register_string( "/lostinfo",         \&lostinfo_handler,         app    => 1, );
DW::Routing->register_string( "/manage2fa",        \&manage2fa_handler,        app    => 1, );
DW::Routing->register_string( "/manage2fa/qrcode", \&manage2fa_qrcode_handler, format => 'png' );

sub account_status_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( form_auth => 1, authas => { showall => 1 } );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};
    my $u      = $rv->{u};
    my $get    = $r->get_args;

    my $ml_scope = "/settings/accountstatus.tt";
    my @statusvis_options =
        $u->is_suspended
        ? ( 'S' => LJ::Lang::ml("$ml_scope.journalstatus.select.suspended") )
        : (
        'V' => LJ::Lang::ml("$ml_scope.journalstatus.select.activated"),
        'D' => LJ::Lang::ml("$ml_scope.journalstatus.select.deleted"),
        );
    my %statusvis_map = @statusvis_options;

    my $errors = DW::FormErrors->new;

    # TODO: this feels like a misuse of DW::FormErrors. Make a new class?
    my $messages = DW::FormErrors->new;
    my $warnings = DW::FormErrors->new;

    my $post;
    if ( $r->did_post && LJ::check_referer('/accountstatus') ) {
        $post = $r->post_args;
        my $new_statusvis = $post->{statusvis};

        # are they suspended?
        $errors->add( "", ".error.nochange.suspend" )
            if $u->is_suspended;

        # are they expunged?
        $errors->add( "", '.error.nochange.expunged' )
            if $u->is_expunged;

        # invalid statusvis
        $errors->add( "", '.error.invalid' )
            unless $new_statusvis eq 'D' || $new_statusvis eq 'V';

        my $did_change = $u->statusvis ne $new_statusvis;

        # no need to change?
        $messages->add(
            "",
            $u->is_community ? '.message.nochange.comm' : '.message.nochange',
            { statusvis => $statusvis_map{$new_statusvis} }
        ) unless $did_change;

        if ( !$errors->exist && $did_change ) {
            my $res = 0;

            my $ip = $r->get_remote_ip;

            my @date = localtime(time);
            my $date = sprintf(
                "%02d:%02d %02d/%02d/%04d",
                @date[ 2, 1 ],
                $date[3],
                $date[4] + 1,
                $date[5] + 1900
            );

            if ( $new_statusvis eq 'D' ) {

                $res = $u->set_deleted;

                $u->set_prop( delete_reason => $post->{reason} || "" );

                if ($res) {

                    # sending ESN status was changed
                    LJ::Event::SecurityAttributeChanged->new(
                        $u,
                        {
                            action   => 'account_deleted',
                            ip       => $ip,
                            datetime => $date,
                        }
                    )->fire;
                }
            }
            elsif ( $new_statusvis eq 'V' ) {
                ## Restore previous statusvis of journal. It may be different
                ## from 'V', it may be read-only, or locked, or whatever.
                my @previous_status =
                    grep { $_ ne 'D' } $u->get_previous_statusvis;
                my $new_status = $previous_status[0] || 'V';
                my $method     = {
                    V => 'set_visible',
                    L => 'set_locked',
                    M => 'set_memorial',
                    O => 'set_readonly',
                    R => 'set_renamed',
                }->{$new_status};
                $errors->add_string( "", "Can't set status '" . LJ::ehtml($new_status) . "'" )
                    unless $method;

                unless ( $errors->exist ) {
                    $res = $u->$method;

                    $u->set_prop( delete_reason => "" );

                    if ($res) {
                        LJ::Event::SecurityAttributeChanged->new(
                            $u,
                            {
                                action   => 'account_activated',
                                ip       => $ip,
                                datetime => $date,
                            }
                        )->fire;

                        $did_change = 1;
                    }
                }
            }

            # error updating?
            $errors->add( "", ".error.db" ) unless $res;

            unless ( $errors->exist ) {
                $messages->add(
                    "",
                    $u->is_community
                    ? '.message.success.comm'
                    : '.message.success',
                    { statusvis => $statusvis_map{$new_statusvis} }
                );

                if ( $new_statusvis eq 'D' ) {
                    $messages->add(
                        "",
                        $u->is_community
                        ? ".message.deleted.comm"
                        : ".message.deleted2",
                        { sitenameshort => $LJ::SITENAMESHORT }
                    );

                    # are they leaving any community admin-less?
                    if ( $u->is_person ) {
                        my $cids = LJ::load_rel_target( $remote, "A" );
                        my @warn_comm_ids;

                        if ($cids) {

                            # verify there are visible maintainers for each community
                            foreach my $cid (@$cids) {
                                push @warn_comm_ids, $cid
                                    unless grep { $_->is_visible }
                                    values
                                    %{ LJ::load_userids( @{ LJ::load_rel_user( $cid, 'A' ) } ) };
                            }

                            # and if not, warn them about it
                            if (@warn_comm_ids) {
                                my $commlist = '<ul>';
                                $commlist .= '<li>' . $_->ljuser_display . '</li>'
                                    foreach values %{ LJ::load_userids(@warn_comm_ids) };
                                $commlist .= '</ul>';

                                $warnings->add(
                                    "",
                                    '.message.noothermaintainer',
                                    {
                                        commlist   => $commlist,
                                        manage_url => LJ::create_url("/communities/list"),
                                        pagetitle  => LJ::Lang::ml('/communities/list.tt.title'),
                                    }
                                );
                            }
                        }

                    }
                }
            }
        }
    }

    my $vars = {
        form_url          => LJ::create_url( undef, keep_args => ['authas'] ),
        extra_delete_text => LJ::Hooks::run_hook( "accountstatus_delete_text", $u ),
        statusvis_options => \@statusvis_options,

        u             => $u,
        delete_reason => $u->prop('delete_reason'),

        errors   => $errors,
        messages => $messages,
        warnings => $warnings,
        formdata => $post,

        authas_form => $rv->{authas_form},
    };
    return DW::Template->render_template( 'settings/accountstatus.tt', $vars );
}

sub manage2fa_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( form_auth => 1 );
    return $rv unless $ok;

    my $r         = $rv->{r};
    my $remote    = $rv->{remote};
    my $post_args = $r->post_args;
    my $errors    = DW::FormErrors->new;

    if ( DW::Auth::TOTP->is_enabled($remote) ) {
        my $vars;

        if ( $post_args->{'action:show-codes'} ) {
            $vars->{codes}      = [ DW::Auth::TOTP->get_recovery_codes($remote) ];
            $vars->{show_codes} = 1;
        }
        elsif ( $post_args->{'action:disable'} ) {
            return DW::Template->render_template('settings/manage2fa/disable.tt');
        }
        elsif ( $post_args->{'action:disable-confirm'} ) {
            if ( !$remote->check_password( $post_args->{password} ) ) {
                $errors->add_string( password => 'Password invalid.' );
                return DW::Template->render_template( 'settings/manage2fa/disable.tt',
                    { errors => $errors } );
            }
            else {
                DW::Auth::TOTP->disable( $remote, $post_args->{password} );

                return DW::Template->render_template( 'settings/manage2fa/index-disabled.tt',
                    { just_disabled => 1 } );
            }
        }

        return DW::Template->render_template( 'settings/manage2fa/index-enabled.tt', $vars );
    }

    # User does not have 2fa
    if ( $post_args->{'action:setup'} ) {
        return DW::Template->render_template( 'settings/manage2fa/setup.tt',
            { totp_secret => DW::Auth::TOTP->generate_secret } );

    }
    elsif ( $post_args->{'action:enable'} ) {
        my $secret      = $post_args->{totp_secret};
        my $verify_code = $post_args->{verification_code};

        if ( !DW::Auth::TOTP->check_code( $remote, $verify_code, secret => $secret ) ) {
            $errors->add_string(
                verification_code => 'Verification code failed. Please, try again.' );
            return DW::Template->render_template( 'settings/manage2fa/setup.tt',
                { totp_secret => $secret, errors => $errors } );
        }

        DW::Auth::TOTP->enable( $remote, $secret );

        return DW::Template->render_template( 'settings/manage2fa/index-enabled.tt',
            { codes => [ DW::Auth::TOTP->get_recovery_codes($remote) ], show_codes => 1 } );
    }

    return DW::Template->render_template('settings/manage2fa/index-disabled.tt');
}

sub manage2fa_qrcode_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $remote = $rv->{remote};

    my $secret = $r->get_args->{'secret'} or die;

    my $qrcode = Imager::QRCode->new( casesensitive => 1, );

    my $image = $qrcode->plot(
        qq{otpauth://totp/Dreamwidth:%20$remote->{user}?secret=$secret&issuer=Dreamwidth});

    my $data;
    $image->write( data => \$data, type => 'png' );
    $r->print($data);

    return $r->OK;
}

sub changepassword_handler {
    my ($opts) = @_;

    my ( $ok, $rv ) = controller( form_auth => 1, anonymous => 1 );
    return $rv unless $ok;

    my $r   = $rv->{r};
    my $get = $r->get_args;
    my $post;

    my $remote = $rv->{remote};

    my ( $aa, $authu );
    my $ml_scope = "/settings/changepassword.tt";
    if ( my $auth = $get->{auth} ) {
        my $lostinfo_url = LJ::create_url("/lostinfo");

        return error_ml("$ml_scope.error.invalidarg")
            unless $auth =~ /^(\d+)\.(.+)$/;

        $aa = LJ::is_valid_authaction( $1, $2 );
        return error_ml("$ml_scope.error.invalidarg")
            unless $aa;

        return error_ml( "$ml_scope.error.actionalreadyperformed", { url => $lostinfo_url } )
            if $aa->{used} eq 'Y';

        return $r->redirect($lostinfo_url)
            unless $aa->{action} eq 'reset_password';

        # confirmed the identity...
        $authu = LJ::load_userid( $aa->{userid} );

        # verify the email can still receive passwords
        return error_ml( "$ml_scope.error.emailchanged", { url => $lostinfo_url } )
            unless $authu->can_receive_password( $aa->{arg1} );
    }
    return error_ml("$ml_scope.error.identity")
        if $remote && $remote->is_identity;

    my $errors = DW::FormErrors->new;
    if ( $r->did_post && $r->post_args->{mode} eq 'submit' ) {
        $post = $r->post_args;

        my $user     = $authu ? $authu->user : LJ::canonical_username( $post->{user} );
        my $password = $post->{password};
        my $newpass1 = LJ::trim( $post->{newpass1} );
        my $newpass2 = LJ::trim( $post->{newpass2} );

        my $u = LJ::load_user($user);
        $errors->add( "user", ".error.invaliduser" ) unless $u;
        $errors->add( "user", ".error.identity" ) if $u && $u->is_identity;
        $errors->add( "user", ".error.changetestaccount" )
            if grep { $user eq $_ } @LJ::TESTACCTS;

        unless ( $errors->exist ) {
            if ( LJ::login_ip_banned($u) ) {
                $errors->add( "user", "error.ipbanned" );
            }
            elsif (!$authu
                && !$u->check_password($password) )
            {
                $errors->add( "password", ".error.badoldpassword" );
                LJ::handle_bad_login($u);
            }
        }

        if ( !$newpass1 ) {
            $errors->add( "newpass1", ".error.blankpassword" );
        }
        elsif ( $newpass1 ne $newpass2 ) {
            $errors->add( "newpass2", ".error.badnewpassword" );
        }
        else {
            my $checkpass = LJ::CreatePage->verify_password(
                password => $newpass1,
                u        => $u
            );
            $errors->add( "newpass1", ".error.badcheck", { error => $checkpass } )
                if $checkpass;
        }

        # don't allow changes if email address is not validated,
        # unless they got the reset email
        $errors->add( "newpass1", ".error.notvalidated" )
            if $u->{status} ne 'A' && !$authu;

        # now let's change the password
        unless ( $errors->exist ) {
            $u->infohistory_add( 'password', 'changed' );
            $u->log_event( 'password_change', { remote => $remote } );
            $u->set_password( $post->{newpass1} );

            # if we used an authcode, we'll need to expire it now
            LJ::mark_authaction_used($aa) if $authu;

            # Kill all sessions, forcing user to relogin
            $u->kill_all_sessions;

            LJ::send_mail(
                {
                    'to'       => $u->email_raw,
                    'from'     => $LJ::ADMIN_EMAIL,
                    'fromname' => $LJ::SITENAME,
                    'charset'  => 'utf-8',
                    'subject'  => LJ::Lang::ml("$ml_scope.email.subject"),
                    'body'     => LJ::Lang::ml(
                        "$ml_scope.email.body2",
                        {
                            sitename => $LJ::SITENAME,
                            siteroot => $LJ::SITEROOT,
                            username => $u->{user},
                        }
                    ),
                }
            );

            my $success_ml =
                $remote
                ? "settings/changepassword.tt.withremote"
                : "settings/changepassword.tt";
            return DW::Controller->render_success(
                $success_ml,
                {
                    url => LJ::create_url("/login"),
                }
            );

            LJ::Hooks::run_hook( 'user_login', $u );
        }
    }

    my $vars = {

        needs_validation => !$authu
            && $remote
            && !$r->did_post
            && $remote->{status} ne 'A',

        authu  => $authu,
        remote => $remote,

        formdata => $post || { user => $remote ? $remote->user : "" },
        errors   => $errors,
    };
    return DW::Template->render_template( 'settings/changepassword.tt', $vars );
}

sub lostinfo_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, anonymous => 1 );
    return $rv unless $ok;

    my $r         = $rv->{r};
    my $form_args = $r->post_args;
    my $captcha   = DW::Captcha->new( 'lostinfo', %{$form_args} );

    my $vars = { captcha => $captcha };

    return DW::Template->render_template( 'settings/lostinfo.tt', $vars )
        unless $r->did_post;

    my $scope = "/settings/lostinfo.tt";
    my $captcha_error;

    return error_ml( "$scope.error.captcha", { errmsg => $captcha_error } )
        unless $captcha->validate( err_ref => \$captcha_error );

    my $ip = $r->get_remote_ip;

    if ( $form_args->{lostpass} ) {

        # this template doesn't exist but the strings do
        $scope = "/settings/lostpass.tt";

        my $email = LJ::trim( $form_args->{email_p} );

        my $u = LJ::load_user( $form_args->{user} );
        return error_ml("error.username_notfound") unless $u;

        return error_ml("$scope.error.syndicated")     if $u->is_syndicated;
        return error_ml("$scope.error.commnopassword") if $u->is_community;
        return error_ml("$scope.error.purged")         if $u->is_expunged;
        return error_ml("$scope.error.renamed")        if $u->is_renamed;

        return error_ml("$scope.error.toofrequent") unless $u->rate_log( "lostinfo", 1 );

        # Check to see if they are banned from sending a password
        if ( LJ::sysban_check( 'lostpassword', $u->user ) ) {
            LJ::Sysban::note(
                $u->id,
                "Password retrieval blocked based on user",
                { user => $u->user }
            );
            return error_ml("$scope.error.sysbanned");
        }

        # Check to see if this email address can receive password reminders
        $email ||= $u->email_raw;
        return error_ml("$scope.error.unconfirmed")
            unless $u->can_receive_password($email);
        return error_ml("$scope.error.invalidemail")
            if $LJ::BLOCKED_PASSWORD_EMAIL && $email =~ /$LJ::BLOCKED_PASSWORD_EMAIL/;

        # email address is okay, build email body
        my $aa = LJ::register_authaction( $u->id, "reset_password", $email );

        my $body = LJ::Lang::ml(
            "$scope.lostpasswordmail.reset",
            {
                lostinfolink => "$LJ::SITEROOT/lostinfo",
                sitename     => $LJ::SITENAME,
                username     => $u->user,
                emailadr     => $u->email_raw,
                resetlink    => "$LJ::SITEROOT/changepassword?auth=$aa->{aaid}.$aa->{authcode}",
            }
        );

        $body .= "\n\n";
        $body .= LJ::Lang::ml( "$scope.lostpasswordmail.ps", { remoteip => $ip } );
        $body .= "\n\n";

        LJ::send_mail(
            {
                to       => $email,
                from     => $LJ::ADMIN_EMAIL,
                fromname => $LJ::SITENAME,
                charset  => 'utf-8',
                subject  => LJ::Lang::ml("$scope.lostpasswordmail.subject"),
                body     => $body,
            }
        ) or die "Error: couldn't send email";

        return DW::Controller->render_success('settings/lostpass.tt');
    }

    if ( $form_args->{lostuser} ) {

        # this template doesn't exist but the strings do
        $scope = "/settings/lostuser.tt";

        my $email = LJ::trim( $form_args->{email_u} );
        return error_ml("$scope.error.no_email") unless $email;

        my @users;
        foreach my $uid ( LJ::User->accounts_by_email($email) ) {
            my $u = LJ::load_userid($uid);
            next if !$u || $u->is_expunged;    # not purged

            # As the idea is to limit spam to one e-mail address,
            # if any of their usernames are over the limit, then
            # don't send them any more e-mail.
            return error_ml("$scope.error.toofrequent") unless $u->rate_log( "lostinfo", 1 );
            push @users, $u->display_name;
        }

        return error_ml( "$scope.error.no_usernames_for_email",
            { address => LJ::ehtml($email) || 'none' } )
            unless @users;

        # we have valid usernames, build email body
        my $userlist = join "\n          ", @users;
        my $body     = LJ::Lang::ml(
            "$scope.email.body",
            {
                sitename     => $LJ::SITENAME,
                emailaddress => $email,
                usernames    => $userlist,
                remoteip     => $ip,
                siteurl      => $LJ::SITEROOT,
            }
        );

        LJ::send_mail(
            {
                to       => $email,
                from     => $LJ::ADMIN_EMAIL,
                fromname => $LJ::SITENAME,
                charset  => 'utf-8',
                subject  => LJ::Lang::ml("$scope.email.subject"),
                body     => $body,
            }
        ) or die "Error: couldn't send email";

        return DW::Controller->render_success('settings/lostuser.tt');
    }

    # have post, but no lostuser or lostpass?
    return error_ml("error.nobutton");
}

1;
