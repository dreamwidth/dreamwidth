#!/usr/bin/perl
#
# DW::Controller::TextCAPTCHA
#
# AJAX endpoint that returns a textCAPTCHA instance
# May also be loaded on a page
#
# Author:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::RPC::TextCAPTCHA;

use strict;

use DW::Routing;
use LJ::JSON;
use DW::Captcha::textCAPTCHA;

# Special case, not using register_rpc here.
DW::Routing->register_regex(
    '/__rpc_captcha/(.*)$',
    \&captcha_handler,
    app     => 1,
    format  => 'html',
    formats => [qw( html json )]
);
DW::Routing->register_regex(
    '^/[^/]+/__rpc_captcha/(.*)$',
    \&captcha_handler,
    user    => 1,
    format  => 'html',
    formats => [qw( html json )]
);

DW::Routing->register_regex(
    '^/captcha/text/(.*)$', \&iframe_captcha_handler,
    app    => 1,
    format => 'html'
);

# loaded inline into the page using JS
sub captcha_handler {
    my ( $call_opts, $auth ) = @_;

    my $from_textcaptcha = DW::Captcha::textCAPTCHA::Logic->get_captcha;
    my ($captcha) = DW::Captcha::textCAPTCHA::Logic::form_data( $from_textcaptcha, $auth );

    if ( $call_opts->format eq "json" ) {

        # json format is for the old JS library
        my $captcha_html = DW::Template->template_string(
            'textcaptcha.tt',
            { captcha  => $captcha },
            { fragment => 1 }
        );

        my $r = DW::Request->get;
        $r->print( to_json( { captcha => $captcha_html } ) );
        return $r->OK;
    }
    else {
        return DW::Template->render_template(
            'textcaptcha.tt',
            { captcha  => $captcha },
            { fragment => 1 }
        );
    }
}

# fallback for the no-js case
sub iframe_captcha_handler {
    my ( $call_opts, $auth ) = @_;

    my $error;
    my $r = DW::Request->get;
    if ( $r->did_post ) {
        my $captcha_object = DW::Captcha->new( undef, %{ $r->post_args } );

    # we don't check whether this is true or not (we'd end up expiring the captcha's auth if we did)
        return DW::Template->render_template(
            'textcaptcha-response.tt',
            { response => DW::Captcha::textCAPTCHA::Logic::to_form_string($captcha_object) },
            { fragment => 1 }
        );
    }

    my $from_textcaptcha = DW::Captcha::textCAPTCHA::Logic->get_captcha;
    my ($captcha) = DW::Captcha::textCAPTCHA::Logic::form_data( $from_textcaptcha, $auth );

    return DW::Template->render_template(
        'textcaptcha.tt',
        {
            handle_submit => 1,

            captcha   => $captcha,
            form_auth => $auth,
            error     => $error
        },
        { fragment => 1 }
    );
}

1;
