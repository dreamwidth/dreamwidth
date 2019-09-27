#!/usr/bin/perl
#
# DW::Controller::Shop::Stripe
#
# Controllers for the Stripe endpoints for the shop.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2019 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Shop::Stripe;

use strict;
use Carp qw/ confess /;
use Digest::SHA qw/ hmac_sha256_hex /;

use LJ::JSON;
use DW::Routing;
use DW::Controller;
use DW::Controller::Shop;
use DW::Shop::Engine::Stripe;

DW::Routing->register_string( '/shop/stripe-checkout', \&stripe_checkout_handler, app => 1 );
DW::Routing->register_string( '/shop/stripe-webhook', \&stripe_webhook_handler, format => 'json' );

sub _stripe_controller {
    my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller(@_);

    if ($ok) {
        $rv->{stripe_published_key} = $LJ::STRIPE{published_key} // '';
    }

    return ( $ok, $rv );
}

sub stripe_checkout_handler {
    my ( $ok, $rv ) = _stripe_controller( anonymous => 1 );
    return $rv unless $ok;

    $rv->{stripe_session_id} = $rv->{cart}->paymentmethod_metadata('session_id');

    return DW::Template->render_template( 'shop/stripe/checkout.tt', $rv );
}

sub stripe_webhook_handler {
    my ( $ok, $rv ) = _stripe_controller( anonymous => 1 );

    my $r        = $rv->{r};
    my $raw_json = $r->content;
    my $event    = from_json($raw_json);

    # validate webhook signature
    my $signature = $r->header_in('Stripe-Signature');
    my %elems     = map { split /=/, $_ } split( /,\s*/, $signature );
    my $payload   = $elems{t} . '.' . $raw_json;
    my $hmac      = hmac_sha256_hex( $payload, $LJ::STRIPE{webhook_key} );
    if ( $hmac ne $elems{v1} ) {
        $r->status(400);
        $r->print('Invalid webhook signature.');
        return $r->OK;
    }

    # Signature validated, process
    my ( $status, $msg ) = DW::Shop::Engine::Stripe->process_webhook($event);
    $r->status($status);
    $r->print($msg);
    return $r->OK;
}

1;
