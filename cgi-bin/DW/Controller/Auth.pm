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

use LWP::UserAgent;

use LJ::JSON;
use LJ::MemCache;
use LJ::Sysban;

use DW::Captcha;
use DW::Controller;
use DW::FormErrors;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/captcha", \&captcha_handler, app => 1 );
DW::Routing->register_string( "/logout",  \&logout_handler,  app => 1 );

sub captcha_handler {
    my ( $ok, $rv ) = controller( anonymous => 1, form_auth => 1, skip_captcha => 1 );
    return $rv unless $ok;

    my $r        = DW::Request->get;
    my $ip       = $r->get_remote_ip;
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

    my $post_args = $r->post_args;
    my $response  = $post_args->{'h-captcha-response'}
        or return $render_captcha_form->();

    # Hit up hCaptcha and ask nicely if this is any good
    my $ua = LWP::UserAgent->new;
    $ua->agent('Dreamwidth Captcha API <accounts@dreamwidth.org>');

    my $res = $ua->post(
        qq{https://hcaptcha.com/siteverify},
        Content =>
qq{response=$response&secret=$LJ::CAPTCHA_HCAPTCHA_SECRET&sitekey=$LJ::CAPTCHA_HCAPTCHA_SITEKEY&remoteip=$ip},
        'Content-Type' => 'application/x-www-form-urlencoded',
    );

    return $render_captcha_form->()
        unless $res->is_success;

    my $obj = from_json( $res->decoded_content );
    if ( $obj->{success} ) {
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
        if ( exists $post_args->{logout_one} ) {
            $remote->logout;
            $vars->{success} = 'one';
        }
        elsif ( exists $post_args->{logout_all} ) {
            $remote->logout_all;
            $vars->{success} = 'all';
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

1;
