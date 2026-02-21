#!/usr/bin/perl
#
# DW::Controller::Login
#
# Login handling
#
# Authors:
#      Momiji <momijizukamori@gmail.com>
#
# Copyright (c) 2015-2024 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Login;

use v5.10;
use strict;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::Auth::Helpers;
use DW::Auth::TOTP;
use DW::Controller;
use DW::FormErrors;
use DW::Routing;
use DW::Template;
use LJ::JSON;

DW::Routing->register_string( '/login',     \&login_handler,     app => 1 );
DW::Routing->register_string( '/login/2fa', \&login_2fa_handler, app => 1 );

# Maximum age of a pending-MFA token in seconds
my $MFA_TOKEN_MAX_AGE = 300;              # 5 minutes
my $MFA_COOKIE_NAME   = 'ljmfapending';

sub login_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, anonymous => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $get    = $r->get_args;
    my $post   = $r->post_args;
    my $remote = $rv->{remote};

    # Set ML scope early so LJ::Lang::ml calls with relative codes (e.g.,
    # '.error.notuser') resolve correctly before render_template runs.
    $r->note( ml_scope => '/login.tt' );

    my $vars = {
        continue_to => $get->{continue_to},
        return_to   => $get->{return_to}
    };

    my @errors = ();

    my $cursess    = $remote ? $remote->session : undef;
    my $old_remote = $remote;

    return error_ml("/login.tt.dbreadonly") if $remote && $remote->readonly;

    my $set_cache = sub { _set_loginout_cache($r) };

    my $logout_remote = sub {
        $remote->kill_session if $remote;
        foreach (qw(BMLschemepref)) {
            $r->delete_cookie( name => $_ ) if $r->cookie($_);
        }
        $remote  = undef;
        $cursess = undef;
        LJ::set_remote(undef);
        LJ::Hooks::run_hooks("post_logout");
    };

    if ( $r->did_post ) {

        # ! after username overrides expire to never
        # < after username overrides ipfixed to yes
        if ( $post->{user} =~ s/([!<]{1,2})$// ) {
            $post->{expire} = 'never' if index( $1, "!" ) >= 0;
            $post->{bindip} = 'yes'   if index( $1, "<" ) >= 0;
        }

        my $user         = LJ::canonical_username( $post->{'user'} );
        my $password     = $post->{'password'};
        my $form_auth_ok = LJ::check_form_auth( $post->{lj_form_auth} );

        my $do_change = $post->{'action:change'};
        my $do_login  = $post->{'action:login'};
        my $do_logout = $post->{'action:logout'};

        # default action is to login:
        if ( !$do_change && !$do_logout ) {
            $do_login = 1;
        }

        # if they're already logged in, change opts
        if ( $do_login && $remote ) {
            $do_login  = 0;
            $do_change = 1;
        }

        # can only change if logged in
        if ( $do_change && not defined $remote ) {
            $do_logout = 1;
            $do_change = 0;
        }

        if ($do_logout) {
            $logout_remote->();
            DW::Stats::increment('dw.action.session.logout');
            $set_cache->();
        }

        if ( $do_change && $form_auth_ok ) {
            my $bindip;
            $bindip = $r->get_remote_ip
                if ( $post->{'bindip'} // '' ) eq "yes";

            my $expire = $post->{expire} // '';
            DW::Stats::increment(
                'dw.action.session.update',
                1,
                [
                    'bindip:' . $bindip             ? 'yes'  : 'no',
                    'exptype:' . $expire eq 'never' ? 'long' : 'short'
                ]
            );
            $cursess->set_ipfixed($bindip) or die "failed to set ipfixed";
            $cursess->set_exptype( $expire eq 'never' ? 'long' : 'short' )
                or die "failed to set exptype";
            $cursess->update_master_cookie;
        }

        if ($do_login) {
            my $u = LJ::load_user($user);

            if ( !$u ) {
                my $euser = LJ::eurl($user);
                push @errors,
                    [
                    unknown_user => LJ::Lang::ml(
                        '.error.notuser', { 'aopts' => "href='$LJ::SITEROOT/create?user=$euser'" }
                    )
                    ]
                    unless $u;
            }
            else {
                push @errors, [ purged_user => LJ::Lang::ml('error.purged.text') ]
                    if $u->is_expunged;
                push @errors, [ memorial_user => LJ::Lang::ml('error.memorial.text') ]
                    if $u->is_memorial;
                push @errors, [ community_disabled_login => LJ::Lang::ml('error.nocommlogin') ]
                    if $u->is_community && !LJ::is_enabled('community-logins');
            }

            if ( $u && $u->is_readonly ) {
                DW::Stats::increment( 'dw.action.session.login_failed',
                    1, ['reason:database_readonly'] );
                return error_ml("/login.tt.dbreadonly");
            }

            my ( $banned, $ok );
            $banned = $ok = 0;

            $ok = LJ::auth_okay( $u, $post->{password}, is_ip_banned => \$banned );

            if ($banned) {
                DW::Stats::increment( 'dw.action.session.login_failed', 1, ['reason:banned_ip'] );
                return error_ml('login.tt.tempfailban');
            }

            # For MFA users: redirect to /login/2fa regardless of password
            # result. This avoids leaking whether the password was correct
            # before the second factor is verified.
            if ( $u && !$u->is_locked && DW::Auth::TOTP->is_enabled($u) ) {
                my ( $exptype, $bindip ) = _session_opts( $r, $post );
                my $returnto = _resolve_return_url( $r, $get, $post );

                my $token = _create_mfa_token(
                    userid      => $u->userid,
                    password_ok => $ok ? 1 : 0,
                    exptype     => $exptype,
                    bindip      => $bindip,
                    returnto    => $returnto // '',
                );

                _set_mfa_cookie( $r, $token );

                $log->info( 'login_mfa_redirect user=', $u->user );
                return $r->redirect("$LJ::SITEROOT/login/2fa");
            }

            if ( $u && !$ok ) {
                push @errors,
                    [
                    bad_password => LJ::Lang::ml(
                        'error.badpassword2', { aopts => "href='$LJ::SITEROOT/lostinfo'" }
                    )
                    ];
            }

            push @errors,
                [ account_locked =>
                    'This account is locked and cannot be logged in to at this time.' ]
                if $u && $u->is_locked;

            if (@errors) {
                DW::Stats::increment( 'dw.action.session.login_failed', 1, ["reason:$_->[0]"] )
                    foreach @errors;    # Many errors, increment a failure for each reason.
            }
            else {
                # at this point, $u is known good (non-MFA)
                $u->preload_props("schemepref");

                my ( $exptype, $bindip ) = _session_opts( $r, $post );

                $u->make_login_session( $exptype, $bindip );
                LJ::Hooks::run_hook( 'user_login', $u );
                $cursess = $u->session;

                DW::Stats::increment( 'dw.action.session.login_ok', 1,
                    [ 'bindip:' . $bindip ? 'yes' : 'no', "exptype:$exptype" ] );
                $log->info( 'login_source=main user=', $u->user );

                LJ::set_remote($u);
                $remote = $u;

                $set_cache->();

                my $redirect_url = _resolve_return_url( $r, $get, $post );
                return $r->redirect($redirect_url) if $redirect_url;

            }

        }
    }

    $vars->{cursess} = $cursess;
    $vars->{errors}  = \@errors;
    $vars->{remote}  = $remote;
    return DW::Template->render_template( 'login.tt', $vars );
}

sub login_2fa_handler {
    my ( $ok, $rv ) = controller( form_auth => 1, anonymous => 1 );
    return $rv unless $ok;

    my $r    = $rv->{r};
    my $post = $r->post_args;

    $r->note( ml_scope => '/login/2fa.tt' );

    my $errors = DW::FormErrors->new;

    # Validate the pending-MFA cookie
    my $token_val = $r->cookie($MFA_COOKIE_NAME);
    my $payload   = _validate_mfa_token($token_val);

    unless ($payload) {
        _clear_mfa_cookie($r);
        return $r->redirect("$LJ::SITEROOT/login");
    }

    my $u = LJ::load_userid( $payload->{userid} );
    unless ( $u && DW::Auth::TOTP->is_enabled($u) ) {
        _clear_mfa_cookie($r);
        return $r->redirect("$LJ::SITEROOT/login");
    }

    if ( $r->did_post ) {
        my $code = $post->{code} // '';
        $code =~ s/\s+//g;    # strip whitespace for usability

        my $valid = 0;

        if ( $code =~ /^\d{6}$/ ) {

            # Looks like a TOTP code
            $valid = DW::Auth::TOTP->check_code( $u, $code );
        }
        elsif ( $code =~ /^[a-z0-9]{4}-[a-z0-9]{4}$/ ) {

            # Looks like a recovery code
            $valid = DW::Auth::TOTP->check_recovery_code( $u, $code );
        }

        if ( $valid && $payload->{password_ok} ) {
            _clear_mfa_cookie($r);

            $u->preload_props("schemepref");
            $u->make_login_session( $payload->{exptype}, $payload->{bindip} );
            LJ::Hooks::run_hook( 'user_login', $u );

            DW::Stats::increment( 'dw.action.session.login_ok', 1,
                [ "exptype:$payload->{exptype}", 'mfa:yes' ] );
            $log->info( 'login_source=main_mfa user=', $u->user );

            LJ::set_remote($u);

            _set_loginout_cache($r);

            my $returnto = $payload->{returnto};
            if ( $returnto && DW::Controller::validate_redirect_url($returnto) ) {
                return $r->redirect($returnto);
            }

            return $r->redirect("$LJ::SITEROOT/");
        }
        else {
            my $reason = !$valid ? 'bad_mfa_code' : 'bad_password_mfa';
            DW::Stats::increment( 'dw.action.session.login_failed', 1, ["reason:$reason"] );
            $errors->add( 'code', '.error.badcredentials' );
        }
    }

    return DW::Template->render_template(
        'login/2fa.tt',
        {
            errors   => $errors,
            formdata => $post,
            user     => $u->display_name,
        }
    );
}

sub _resolve_return_url {
    my ( $r, $get, $post ) = @_;

    my $url;
    if ( $post->{returnto} ) {
        $url = $post->{returnto};
        $url = $LJ::SITEROOT . $url if $url =~ /^\//;
    }
    elsif ( $post->{ret} && $post->{ret} != 1 ) {
        $url = $post->{ret};
    }
    elsif ($get->{'ret'} && $get->{'ret'} == 1
        || $post->{'ret'} && $post->{'ret'} == 1 )
    {
        $url = $r->header_out('Referer');
    }

    return undef unless $url && DW::Controller::validate_redirect_url($url);
    return $url;
}

sub _session_opts {
    my ( $r, $post ) = @_;

    my $exptype =
        ( ( $post->{'expire'} // '' ) eq "never" || $post->{'remember_me'} )
        ? "long"
        : "short";
    my $bindip = ( ( $post->{'bindip'} // '' ) eq "yes" ) ? $r->get_remote_ip : "";

    return ( $exptype, $bindip );
}

sub _create_mfa_token {
    my (%args) = @_;

    my $payload = to_json(
        {
            userid      => $args{userid},
            password_ok => $args{password_ok},
            exptype     => $args{exptype},
            bindip      => $args{bindip},
            returnto    => $args{returnto},
            timestamp   => time(),
        }
    );
    return DW::Auth::Helpers->encrypt_token($payload);
}

sub _validate_mfa_token {
    my ($token) = @_;
    return undef unless $token;

    my $payload = eval { from_json( DW::Auth::Helpers->decrypt_token($token) ) };
    return undef if $@ || !$payload;

    # Check expiration
    my $age = time() - ( $payload->{timestamp} // 0 );
    return undef if $age > $MFA_TOKEN_MAX_AGE || $age < 0;

    return $payload;
}

sub _set_mfa_cookie {
    my ( $r, $token ) = @_;
    $r->add_cookie(
        name     => $MFA_COOKIE_NAME,
        value    => $token,
        httponly => 1,
        path     => '/login',
    );
}

sub _clear_mfa_cookie {
    my ($r) = @_;
    $r->delete_cookie(
        name => $MFA_COOKIE_NAME,
        path => '/login',
    );
}

# Briefly marks the user's uniq as recently logged-in/out so downstream
# pages avoid serving stale cached content.
sub _set_loginout_cache {
    my ($r) = @_;
    my $uniq = $r->note('uniq');
    LJ::MemCache::set( "loginout:$uniq", 1, time() + 15 ) if $uniq;
}

1;
