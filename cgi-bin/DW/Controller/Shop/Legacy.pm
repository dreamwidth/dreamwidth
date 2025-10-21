#!/usr/bin/perl
#
# DW::Controller::Shop::Legacy
#
# Define legacy pages for processors we no longer actively support.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Shop::Legacy;

use strict;

use DW::Shop;
use DW::Routing;
use DW::Template;
use DW::Controller;
use DW::Controller::Shop;
use DW::Shop::Engine::PayPal;
use DW::Shop::Engine::GoogleCheckout;

DW::Routing->register_string( '/shop/pp_notify',  \&pp_notify_handler,  app => 1 );
DW::Routing->register_string( '/shop/gco_notify', \&gco_notify_handler, app => 1 );
DW::Routing->register_string( '/shop/creditcard', \&pp_button_handler,  app => 1 );

sub pp_notify_handler {

    # Pass through notification support for PayPal to give us status updates about
    # something or other happening to one of our outstanding payments.
    #
    my $r         = DW::Request->get;
    my $form_args = $r->did_post ? $r->post_args : $r->get_args;

    my $process_ok = DW::Shop::Engine::PayPal->process_ipn($form_args);

    $r->print( $process_ok ? "notified" : "failure" );
    return $r->OK;
}

sub gco_notify_handler {

    # Same as above, except for Google Checkout.
    #
    my $r         = DW::Request->get;
    my $form_args = $r->did_post ? $r->post_args : $r->get_args;

    my $process_ok = DW::Shop::Engine::GoogleCheckout->process_notification($form_args);

    # not sure why this one never even tried...
    $r->print("failure");
    return $r->OK;
}

sub pp_button_handler {

    # Original page comment, preserved for hilarity:
    #
    # Generates HTML for a PayPal "Buy Now" button... maybe in the future this
    # will do something far more amazing, with super robot powers.
    #
    # Called from DW::Shop::Engine::CreditCardPP->checkout_url
    # -- was this ever actually useful? who knows any more?
    #
    my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller( anonymous => 1 );
    return $rv unless $ok;

    my $r     = DW::Request->get;
    my $scope = "/shop/legacy/pp_button.tt";
    my $cart  = $rv->{cart};

    return error_ml("$scope.error.nocart") unless $cart;
    return error_ml("$scope.error.emptycart") unless $cart->has_items;

    # if state is NOT open, then just redirect them to the wait page,
    # which will do the Right Thing.  this typically is used in the case
    # that the user double clicks on the form, or hits back and clicks
    # submit again...
    return $r->redirect( "$LJ::SITEROOT/shop/receipt?ordernum=" . $cart->ordernum )
        unless $cart->state == $DW::Shop::STATE_OPEN;

    # if they have a $0 cart, we don't support that yet
    return error_ml("$scope.error.zerocart") if $cart->total_cash == 0.00;

    # looks good, set the payment method and state
    $cart->paymentmethod('creditcardpp');
    $cart->state($DW::Shop::STATE_PEND_PAID);

    # values we need
    my $vars = {
        cartid     => $cart->id,
        cost       => $cart->display_total_cash,
        pp_cc_url  => $LJ::PAYPAL_CONFIG{cc_url},
        pp_account => $LJ::PAYPAL_CONFIG{account},
        buynow_bn  => $LJ::SITENAMESHORT . '_BuyNow_WPS_US',
        notify_url => $LJ::SITEROOT . '/shop/pp_notify',
        item_name  => "$LJ::SITECOMPANY Order #" . $cart->id
    };

    return DW::Template->render_template( 'shop/legacy/pp_button.tt', $vars );
}

1;
