#!/usr/bin/perl
#
# DW::Controller::Shop::CreditCard
#
# Define pages for unspecified card processor (unused since switching to Stripe).
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

package DW::Controller::Shop::CreditCard;

use strict;

use DW::Shop;
use DW::Routing;
use DW::Template;
use DW::Controller;
use DW::Controller::Shop;
use DW::Shop::Engine::CreditCard;

DW::Routing->register_string( '/shop/creditcard_wait', \&cc_wait_handler,  app => 1 );

sub cc_wait_handler {

    # This page is a fairly simple "please wait while we try to charge you"
    # page that refreshes every 5 seconds until we have gotten a result.
    #
    # (redirected here from /shop/entercc)
    #
    my ( $ok, $rv ) = _shop_controller( anonymous => 1 );
    return $rv unless $ok;

    my $r         = DW::Request->get;
    my $form_args = $r->get_args;
    my $scope     = "/shop/cc/creditcard_wait.tt";

    # cart is loaded in _shop_controller but we want to be sure
    # it's the one that used get_from_ordernum with form data
    my $cart = $rv->{cart};
    return error_ml("$scope.error.nocart")
        unless $cart && $form_args->{ordernum};

    # establish the engine they're trying to use
    my $eng = DW::Shop::Engine->get( creditcard => $cart );
    return error_ml("$scope.error.invalidpaymentmethod") unless $eng;

    # get the transaction row
    my $cctransid = ( $form_args->{cctransid} // 0 ) + 0;
    my $row       = $eng->get_transaction($cctransid);
    die "Row not for cart, that's no good!\n"    # trying to spoof us?
        unless $row
        && $row->{cctransid} == $cctransid
        && $row->{cartid} == $cart->id;

    # if the job failed, redirect back to the cart, but print
    # a different error message if it was flagged as a duplicate
    if ( $row->{jobstate} eq 'failed' ) {
        my $errtype = $row->{responsetext} =~ /^Duplicate transaction / ? 'duplicate' : 'failed';
        return $r->redirect("$LJ::SITEROOT/shop/cart?$errtype=1");
    }

    die "Sorry, unknown state: $row->{jobstate}.\n"
        unless $row->{jobstate} =~ /^(?:paid|queued|internal_failure)$/;

    # values we need to print the page if we didn't bail out above
    my $vars = {
        jobstate => $row->{jobstate},
        ordernum => $form_args->{ordernum},
        no_email => $cart->userid ? 0 : 1,
    };

    return DW::Template->render_template( 'shop/cc/creditcard_wait.tt', $vars );
}

1;
