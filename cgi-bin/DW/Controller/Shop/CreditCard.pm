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

use Business::CreditCard;
use DW::Countries;

DW::Routing->register_string( '/shop/creditcard_wait', \&cc_wait_handler,  app => 1 );
DW::Routing->register_string( '/shop/entercc',         \&enter_cc_handler, app => 1 );

sub cc_wait_handler {

    # This page is a fairly simple "please wait while we try to charge you"
    # page that refreshes every 5 seconds until we have gotten a result.
    #
    # (redirected here from /shop/entercc)
    #
    my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller( anonymous => 1 );
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

sub enter_cc_handler {

    # Called from DW::Shop::Engine::CreditCard->checkout_url
    #
    # Checkout page for letting the user enter credit card details.
    # WARNING: this page ABSOLUTELY requires SSL, unless we're in a development
    # environment, and MUST NOT store credit card information ANYWHERE.
    # There are legal ramifications if we were to store the information on our
    # servers, or pass it around in any sort of unencrypted manner!
    #
    my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller( anonymous => 1, form_auth => 1 );
    return $rv unless $ok;

    my $r     = DW::Request->get;
    my $scope = "/shop/cc/entercc.tt";
    my $vars  = {};

    my $cart = $rv->{cart};

    return error_ml("$scope.error.nocart") unless $cart;
    return error_ml("$scope.error.emptycart") unless $cart->has_items;

    # if state is NOT open, then just redirect them to the wait page,
    # which will do the Right Thing.  this typically is used in the case
    # that the user double clicks on the form, or hits back and clicks
    # submit again...
    return $r->redirect( "$LJ::SITEROOT/shop/creditcard_wait?ordernum="
            . $cart->ordernum
            . "&cctransid="
            . $cart->{cctransid} )
        unless $cart->state == $DW::Shop::STATE_OPEN;

    # if they have a $0 cart, we don't support that yet
    return error_ml("$scope.error.zerocart") if $cart->total_cash == 0.00;

    # finished validating cart; now to solicit and check CC form data
    {
        $vars->{cart} = $cart;

        # make a copy so we can safely delete keys
        $vars->{formdata} = { %{ $r->post_args } };

        # don't propagate these values back to the form, make them retype
        delete $vars->{formdata}->{ccnum};
        delete $vars->{formdata}->{cvv2};

        # load country codes, and US states
        my ( %countries, %usstates );
        DW::Countries->load( \%countries );
        LJ::load_codes( { state => \%usstates } );

        # now sort the above appropriately
        my @countries = (
            '--' => '',
            US   => 'United States',
            map { $_ => $countries{$_} } sort { $countries{$a} cmp $countries{$b} }
                keys %countries
        );
        my @usstates = (
            '--' => '(select state)',
            map { $_ => $usstates{$_} } sort { $usstates{$a} cmp $usstates{$b} }
                keys %usstates
        );

        $vars->{countries} = \@countries;
        $vars->{usstates}  = \@usstates;

        # accepted credit card list.  this should be populated by the hooks.
        my $accepted_ccs = '(failed to get list of accepted credit cards)';
        LJ::Hooks::run_hook( 'creditcard_accepted_ccs', \$accepted_ccs );
        $vars->{accepted_ccs} = $accepted_ccs;

        # calculate which years to accept for the expiration date
        my $startyear = ( localtime() )[5] + 1900;    # current year
        my $endyear   = $startyear + 10;              # ten years from now

        $vars->{accepted_years} = [ map { $_ => $_ } $startyear .. $endyear ];

        $vars->{accepted_months} =
            [ map { $_ => sprintf( '%s - %0.2d', LJ::Lang::month_long_ml($_), $_ ) } 1 .. 12 ];

        # for cc_charge_from
        $vars->{run_hook} = sub { LJ::Hooks::run_hook( $_[0] ) };
    }

    $vars->{err} = {};

    return DW::Template->render_template( 'shop/cc/entercc.tt', $vars )
        unless $r->did_post;

    # time for error checking posted data
    my %err;

    my $go_back_with_errors = sub {

        # set the rest of the CC errors so the person can retype
        $err{ccnum} ||= '.error.reinput';
        $err{cvv2}  ||= '.error.reinput';

        $vars->{err} = \%err;

        return DW::Template->render_template( 'shop/cc/entercc.tt', $vars );
    };

    my $form_args = $r->post_args;

    # check for errors... first, make sure we get everything that is required
    my %in;
    foreach my $name (
        qw/ firstname lastname street1 street2 city country
        zip phone ccnum cvv2 expmon expyear /
        )
    {
        my $val = LJ::trim( $form_args->{$name} );
        $val =~ s/\s+/ /;    # canonicalize to single spaces

        # double hyphens are special
        $val = '' if $val eq '--';

        # everything is required...except street2 or phone
        unless ( $val || $name eq 'street2' || $name eq 'phone' ) {
            $err{$name} = '.error.required';
            next;
        }

        # okay, we know we got something, validate the numerics
        $in{$name} = $val;
    }

    # if US or CA, then state must be provided
    if ( defined $in{country} ) {
        $err{state} = '.error.required'
            if ( $in{country} eq 'US' && $form_args->{usstate} !~ /^\w\w$/ )
            || ( $in{country} eq 'CA' && $form_args->{otherstate} !~ /\S/ );
    }

    # if we found any missing field errors, then return to handle them now
    return $go_back_with_errors->() if %err;

    # must be valid states by now
    $in{state} = LJ::trim( $form_args->{ $in{country} eq 'US' ? 'usstate' : 'otherstate' } );

    # now do some more checking
    $err{cvv2}   = '.error.cvv2.invalid' unless $in{cvv2} =~ /^\d\d\d\d?$/;
    $err{expmon} = '.error.required'     unless $in{expmon} >= 1 && $in{expmon} <= 12;

    my $endyear = $vars->{accepted_years}->[-1];
    $err{expyear} = '.error.required'
        unless $in{expyear} >= 2010 && $in{expyear} <= $endyear;

    # validating the credit card is more intense - use Business::CreditCard rules
    $in{ccnum} =~ s/\D//g;    # remove all non-numerics
    $err{ccnum} = '.error.ccnum.invalid' unless validate( $in{ccnum} );

    # verify that the zip code is right for US
    $err{zip} = '.error.zip.invalidus'
        if $in{country} eq 'US' && $in{zip} !~ /^(?:\d\d\d\d\d)(?:-?\d\d\d\d)?$/;

    # final error check before processing
    return $go_back_with_errors->() if %err;

    # establish the engine they're trying to use
    my $eng = DW::Shop::Engine->get( creditcard => $cart );
    return error_ml("$scope.error.invalidpaymentmethod") unless $eng;

    # set the payment method on the cart
    $cart->paymentmethod('creditcard');
    $cart->state($DW::Shop::STATE_PEND_PAID);

    # stuff a new row in the database
    my $cctransid = $eng->setup_transaction( %in, cartid => $cart->id, ip => $r->get_remote_ip );
    return error_ml("$scope.error.megafail") unless $cctransid && $cctransid > 0;

    # FIXME: mega hack, we're depending on the storable state of the cart here
    # and this should really be in a db row somewhere so we can reverse it
    $cart->{cctransid} = $cctransid;
    $cart->save;

    # redirect to the waiting page now
    return $r->redirect( "$LJ::SITEROOT/shop/creditcard_wait?ordernum="
            . $cart->ordernum
            . "&cctransid=$cctransid" );
}

1;
