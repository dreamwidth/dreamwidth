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

use DW::Routing;
use DW::Template;
use DW::Controller;
use DW::FormErrors;
use DW::AccountSwitcher;
use DW::Auth::Login;
use DW::Auth::TOTP;

# no_cache: the login form embeds a form_auth (CSRF) token that, for logged-out
# users, is bound to their per-browser ljuniq cookie. If a shared proxy caches
# this page, everyone is served one user's token and their login POST fails with
# "Invalid form submission". (The pre-TT login.bml set nocache=>1 for the same
# reason; /register and /openid carry no_cache => 1 likewise.)
DW::Routing->register_string( '/login', \&login_handler, app => 1, no_cache => 1 );

DW::Routing->register_string( '/login/2fa', \&login_2fa_handler, app => 1, no_cache => 1 );

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

    # The page to send the user back to after a successful login. Prefer the
    # POSTed value (form resubmission) over the GET value so a failed login
    # attempt keeps the destination. Validate it before storing or redirecting
    # so external destinations and header injection cannot enter the flow.
    my $returnto = $post->{returnto} // $get->{returnto};
    $returnto //= $post->{ret}             if $post->{ret} && $post->{ret} ne '1';
    $returnto //= $r->header_in('Referer') if ( $post->{ret} // $get->{ret} // '' ) eq '1';
    $returnto = DW::Auth::Login->return_url($returnto);

    # "add another account" intent: a login submitted while already logged in
    # should add a session rather than change the current one's options.
    my $store_only = ( $post->{store_only} || $get->{store_only} ) ? 1 : 0;
    my $adding = ( $post->{switch} || $get->{switch} || $store_only ) ? 1 : 0;

    my $vars = {
        continue_to => $get->{continue_to},

        # forwarded into the login form (components/login.tt) as a hidden field
        # so that, after a successful login, we send the user back to the page
        # they were trying to reach when they got bounced here by needlogin().
        returnto => $returnto,

        # render the login form (not the change-options form) even when logged
        # in, so the user can sign in to an additional account.
        add_account => $adding,
        store_only  => $store_only,

        # canonicalized so a reflected ?user= can't inject markup into the form
        prefill_user => LJ::canonical_username( $get->{user} // '' ),
    };

    my @errors = ();

    my $cursess    = $remote ? $remote->session : undef;
    my $old_remote = $remote;

    return error_ml("/login.tt.dbreadonly") if $remote && $remote->readonly;

    my $set_cache = sub {

        # changes some responses if user has recently logged in/out to prevent browsers
        # from caching stale data on some pages.
        my $uniq = $r->note('uniq');
        LJ::MemCache::set( "loginout:$uniq", 1, time() + 15 ) if $uniq;

    };

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

        # if they're already logged in, change opts -- unless they're adding
        # another account, in which case treat it as a fresh login
        if ( $do_login && $remote && !$adding ) {
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
                # at this point, $u is known good
                $u->preload_props("schemepref");

                my $exptype =
                    ( ( $post->{'expire'} // '' ) eq "never" || $post->{'remember_me'} )
                    ? "long"
                    : "short";
                my $bindip = ( ( $post->{'bindip'} // '' ) eq "yes" ) ? $r->get_remote_ip : "";

                my %completion = (
                    exptype    => $exptype,
                    bindip     => $bindip,
                    adding     => $adding,
                    store_only => $store_only,
                    returnto   => $returnto
                );
                if ( DW::Auth::TOTP->is_enabled($u) ) {
                    my $token = DW::Auth::Login->begin( $u, %completion );
                    return error_ml('error.invalidform') unless $token;
                    $r->add_cookie(
                        name     => 'ljmfapending',
                        value    => $token,
                        httponly => 1,
                        SameSite => 'Lax',
                        path     => '/login'
                    );
                    return $r->redirect("$LJ::SITEROOT/login/2fa");
                }
                DW::Auth::Login->complete( $u, %completion )
                    or return error_ml('error.invalidform');
                $cursess = $u->session;

                DW::Stats::increment( 'dw.action.session.login_ok', 1,
                    [ 'bindip:' . $bindip ? 'yes' : 'no', "exptype:$exptype" ] );

                $remote = LJ::get_remote();

                $set_cache->();

                if ($returnto) {
                    my $redirect_url = $returnto;
                    $redirect_url =~ s/#.*$// if $store_only;
                    $redirect_url .= '#post-as-' . $u->id if $store_only;
                    return $r->redirect($redirect_url);
                }

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
    my $r     = $rv->{r};
    my $token = $r->cookie('ljmfapending');
    my ( $u, $opts ) = DW::Auth::Login->pending($token);
    unless ($u) {
        $r->delete_cookie( name => 'ljmfapending', path => '/login' );
        return $r->redirect("$LJ::SITEROOT/login");
    }
    my $errors = DW::FormErrors->new;
    $r->note( ml_scope => '/login/2fa.tt' );
    if ( $r->did_post ) {
        my ( $verified, $completion ) = DW::Auth::Login->verify( $token, $r->post_args->{code} );
        if ($verified) {
            DW::Auth::Login->complete( $verified, %$completion, mfa_verified => 1 )
                or return error_ml('error.invalidform');
            $r->delete_cookie( name => 'ljmfapending', path => '/login' );
            my $url = $completion->{returnto};
            $url = DW::Auth::Login->return_url($url) || "$LJ::SITEROOT/";
            if ( $completion->{store_only} ) {
                $url =~ s/#.*$//;
                $url .= '#post-as-' . $verified->id;
            }
            return $r->redirect($url);
        }
        $errors->add( 'code', '.error.badcredentials' );
    }
    return DW::Template->render_template( 'login/2fa.tt',
        { errors => $errors, user => $u->display_name } );
}
1;
