#!/usr/bin/perl
#
# DW::Controller::Auth
#
# This controller is for authentication endpoints. Login, logout, and other
# related functionality.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2017-2022 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Auth;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::AccountSwitcher;
use DW::Captcha;
use DW::Controller;
use DW::FormErrors;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/captcha",         \&captcha_handler,         app => 1 );
DW::Routing->register_string( "/logout",          \&logout_handler,          app => 1 );
DW::Routing->register_string( "/switchaccount",   \&switch_handler,          app => 1 );
DW::Routing->register_string( "/manage/accounts", \&manage_accounts_handler, app => 1 );

sub captcha_handler {
    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1, skip_captcha => 1 );
    return $rv unless $ok;

    my $r        = DW::Request->get;
    my $get_args = $r->get_args;

    # Renderer for GETs
    my $render_captcha_form = sub {
        return DW::Template->render_template( 'auth/captcha.tt',
            { sitekey => $LJ::CAPTCHA_HCAPTCHA_SITEKEY, returnto => $get_args->{returnto} } );
    };
    return $render_captcha_form->()
        unless $r->did_post;

    # If it was a POST and it had the reset get var, just wipe it and do
    # absolutely nothing else
    if ( $get_args->{reset} ) {
        DW::Captcha->reset_captcha;
        return $render_captcha_form->();
    }

    # Validate the response through the standard captcha abstraction, which is
    # the single place that talks to the hCaptcha siteverify API.
    my $post_args = $r->post_args;
    my $captcha   = DW::Captcha->new( undef, %{ $post_args || {} } );
    if ( $captcha->validate ) {
        DW::Captcha->record_success( $rv->{remote} );
        if ( DW::Controller::validate_redirect_url( $post_args->{returnto} ) ) {
            return $r->redirect( $post_args->{returnto} );
        }
    }

    # Something has gone wrong, just redirect back to the main page in
    # basically a captcha loop (hopefully they can fix their stuff)
    return $render_captcha_form->();
}

sub logout_handler {

    # We have to allow anonymous viewers because that's how we render the page that
    # tells the user they have successfully logged out
    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r      = DW::Request->get;
    my $remote = $rv->{remote};
    my $vars   = { returnto => $r->get_args->{'returnto'} // '', };

    if ( $remote && $r->did_post ) {
        my $post_args = $r->post_args;

        # After ending the active account's session(s), hand off to another
        # account signed in to this browser if there is one; otherwise finish a
        # normal logout and forget the switcher's stored accounts.
        my $finish_logout = sub {
            my $default_success = shift;
            if ( my $next = DW::AccountSwitcher->promote_next ) {
                $vars->{success}     = 'switched';
                $vars->{switched_to} = $next->ljuser_display;
            }
            else {
                $remote->_logout_common;
                DW::AccountSwitcher->clear;
                $vars->{success} = $default_success;
            }
        };

        if ( exists $post_args->{logout_one} ) {
            if ( my $sess = $remote->session ) {
                $sess->destroy;
            }
            $finish_logout->('one');
        }
        elsif ( exists $post_args->{logout_all} ) {
            LJ::Session->destroy_all_sessions($remote);
            $finish_logout->('all');
        }

        # If the logout form asked to be sent back to the original page (with a
        # hidden 'ret=1' form input and a return url), do so (as long as the logout
        # was successful).
        if ( $vars->{success} && $post_args->{returnto} && $post_args->{ret} ) {
            if ( LJ::check_referer( '', $post_args->{returnto} ) ) {
                return $r->redirect( $post_args->{returnto} );
            }
        }
    }

    # GET case or the logout success case
    return DW::Template->render_template( 'auth/logout.tt', $vars );
}

# Switch the active account to another one signed in to this browser, or remove
# one from the switcher. POST-only and CSRF-protected. Always redirects.
sub switch_handler {
    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r = DW::Request->get;
    return $r->redirect("$LJ::SITEROOT/login") unless $r->did_post;

    my $post     = $r->post_args;
    my $returnto = $post->{returnto};

    my $back = sub {
        if ($returnto) {

            # a local absolute path (our own manage page, etc.) is safe to honor
            # directly; the leading "/" without a second one rules out
            # protocol-relative "//evil.com" redirects
            return $r->redirect($returnto) if $returnto =~ m{^/(?!/)};

            # otherwise only honor a full same-site URL
            return $r->redirect($returnto) if LJ::check_referer( '', $returnto );
        }
        return $r->redirect("$LJ::SITEROOT/");
    };

    # remove a stored account from this browser, leaving the active one alone
    if ( my $rm = $post->{remove_userid} ) {
        DW::AccountSwitcher->remove_account($rm);
        return $back->();
    }

    my $userid = $post->{userid} + 0;
    my $result = DW::AccountSwitcher->switch_to($userid);

    # session gone or unknown: send to a pre-filled login (Google-style)
    if ( $result ne '1' ) {
        my $u   = LJ::load_userid($userid);
        my $url = "$LJ::SITEROOT/login?switch=1";
        $url .= "&user=" . LJ::eurl( $u->user )    if $u;
        $url .= "&returnto=" . LJ::eurl($returnto) if $returnto;
        return $r->redirect($url);
    }

    return $back->();
}

# Management page for the account switcher: list the accounts signed in to this
# browser, switch to or remove any of them, or add another. The switch/remove
# actions post to /switchaccount; adding goes through /login?switch=1.
sub manage_accounts_handler {
    my ( $ok, $rv ) = controller();
    return $rv unless $ok;

    my $remote = $rv->{remote};

    # Every account signed in to this browser (current + switchable) in one
    # alphabetical list, the current one flagged inline so that switching moves
    # only the flag and never reorders the rows.
    my @accounts = sort { $a->{user} cmp $b->{user} } (
        { u => $remote, user => $remote->user, current => 1, valid => 1 },
        map {
            { %$_, current => 0 }
        } DW::AccountSwitcher->accounts,
    );

    return DW::Template->render_template(
        'manage/accounts.tt',
        {
            accounts => \@accounts,
            returnto => "$LJ::SITEROOT/manage/accounts",
        }
    );
}

1;
