#!/usr/bin/perl
#
# DW::Shop::Engine::GoogleCheckout
#
# The interface to Google Checkout's flow.  Responsible for doing all of the
# work to talk to this merchant processor.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop::Engine::GoogleCheckout;

use strict;
use Carp qw/ croak confess /;
use Storable qw/ nfreeze thaw /;

# put these in an eval ... most people won't actually be using Google Checkout,
# so we don't want to force (e.g.) development environments to have to install
# these modules.  however, if someone DOES want to use GCO, then they need to
# make sure these modules are installed ...
BEGIN {
    my $rv = eval <<USE;
use Google::Checkout::General::GCO;
use Google::Checkout::General::MerchantCheckoutFlow;
use Google::Checkout::General::DigitalContent;
use Google::Checkout::General::ShoppingCart;
use Google::Checkout::Command::ChargeOrder;
use Google::Checkout::General::Util qw/ is_gco_error /;
1;
USE

    # This restricts the warning to only print in web context,
    # which allows t/00-compile.t to succeed without GC modules.
    # There's no way to use LJ::is_enabled( 'googlecheckout' )
    # without changing the module load order for the entire system.
    warn "NOTE: Google::Checkout::* Perl modules were not found.\n"
        if !$rv and ( $^X =~ /apache/ );

    # avoid compile error, if we don't have the google checkout modules installed
    our $EMAIL_DELIVERY =
        eval { no strict "subs"; Google::Checkout::General::DigitalContent::EMAIL_DELIVERY };
}

use base qw/ DW::Shop::Engine /;

# new( $cart )
#
# instantiates a new GCO engine for the given cart
sub new {
    return bless { cart => $_[1] }, $_[0];
}

# new_from_cart( $cart )
#
# constructs an engine from a given cart.
sub new_from_cart {
    my ( $class, $cart ) = @_;

    my $dbh = DW::Pay::get_db_writer()
        or die "Database temporarily unavailable.\n";    # no object yet

    my ( $gcoid, $cn, $em ) =
        $dbh->selectrow_array( 'SELECT gcoid, contactname, email FROM gco_map WHERE cartid = ?',
        undef, $cart->id );

    # if they have no row in the database, then this is a new cart that hasn't
    # yet really been through the flow
    return bless { cart => $cart }, $class
        unless $gcoid;

    # it HAS, we have a row, so populate with all of the data we have
    return bless {
        gcoid       => $gcoid,
        contactname => $cn,
        email       => $em,
        cart        => $cart,
    }, $class;
}

# new_from_gcoid( $gcoid )
#
# constructs an engine from a given google order number.
sub new_from_gcoid {
    my ( $class, $gcoid ) = @_;

    my $dbh = DW::Pay::get_db_writer()
        or die "Database temporarily unavailable.\n";    # no object yet

    my ( $cartid, $cn, $em ) =
        $dbh->selectrow_array( 'SELECT cartid, contactname, email FROM gco_map WHERE gcoid = ?',
        undef, $gcoid );

    my $cart = DW::Shop::Cart->get_from_cartid($cartid)
        or die "Unable to load cart from Google Order Number $gcoid.\n";

    # it HAS, we have a row, so populate with all of the data we have
    return bless {
        gcoid       => $gcoid,
        contactname => $cn,
        email       => $em,
        cart        => $cart,
    }, $class;
}

# checkout_url()
#
# given a shopping cart full of Stuff, build a URL for us to send the user to
# to initiate the checkout process.
sub checkout_url {
    my $self = $_[0];

    # make sure that the cart contains something that costs something.  since
    # this check should have been done above, we die hardcore here.
    my $cart = $self->cart;
    die "Constraints not met: cart && cart->has_items && cart->total_cash > 0.00.\n"
        unless $cart && $cart->has_items && $cart->total_cash > 0.00;

    # and, just in case something terrible happens, make sure our state is good
    die "Cart not in valid state!\n"
        unless $cart->state == $DW::Shop::STATE_OPEN;

    # flow for this particular order
    my $flow = Google::Checkout::General::MerchantCheckoutFlow->new(
        edit_cart_url         => "$LJ::SITEROOT/shop/cart",
        continue_shopping_url => "$LJ::SITEROOT/shop",
        buyer_phone           => 'false',
    );

    # and now build us a cart
    my $gcart = Google::Checkout::General::ShoppingCart->new(
        expiration    => "+1 month",
        private       => $cart->id,
        checkout_flow => $flow,
    );

    # now we have to stick in data for each of the items in the cart
    foreach my $item ( @{ $cart->items } ) {
        my $gitem = Google::Checkout::General::DigitalContent->new(
            name            => $item->class_name,
            description     => $item->short_desc,
            price           => $item->cost_cash,
            quantity        => 1,
            private         => $item->id,
            delivery_method => $DW::Shop::Engine::GoogleCheckout::EMAIL_DELIVERY,
        );

        $gcart->add_item($gitem);
    }

    # now get a URL from Google, or try
    my $res = $self->gco->checkout($gcart);
    return $self->error("Google Checkout Error: $res")
        if is_gco_error $res;

    # and finally, this is the URL!
    return $res;
}

# cancel_order()
#
# cancels the order and doesn't send any money
sub cancel_order {

    # does not apply to this payment system ...
    die "Does not apply to Google Checkout.\n";
}

# this sends the command to Google Checkout to actually charge the order.  it must
# be open and have a GON/GCOID which means it went through the new order flow.
sub charge_order {
    my $self = $_[0];
    return
        unless $self->gcoid > 0
        && $self->cart->state == $DW::Shop::STATE_OPEN;

    my $charge_order = Google::Checkout::Command::ChargeOrder->new(
        order_number => $self->gcoid,
        amount       => $self->cart->total_cash,
    );

    my $response = $self->gco->command($charge_order);
    die "Failed to charge order: $response\n"
        if is_gco_error $response;

    # we are now pending payment for this cart ...
    $self->cart->state($DW::Shop::STATE_PEND_PAID);
}

# called by the system when we get a posted notification of some sort
sub process_notification {
    my ( $class, $form ) = @_;

    # if no order number, invalid!
    my $gon = $form->{'google-order-number'}
        or return;

    # log the request
    my $dbh = DW::Pay::get_db_writer()
        or die "failed, please retry later\n";
    $dbh->do(
        q{INSERT INTO gco_log (gcoid, ip, transtime, req_content)
          VALUES (?, ?, UNIX_TIMESTAMP(), ?)},
        undef, $gon, BML::get_remote_ip(), nfreeze($form)
    );
    die "failed to insert: " . $dbh->errstr . "\n"
        if $dbh->err;

    # now that it's logged, we can do some processing depending on what type it is
    if ( $form->{_type} eq 'new-order-notification' ) {
        my $cart;
        $cart = DW::Shop::Cart->get_from_cartid($1)
            if $form->{'shopping-cart.merchant-private-data'} =~ m!note>(\d+)</merch!;

        # now ensure the cart is good ...
        return 1
            unless $cart
            && $cart->state == $DW::Shop::STATE_OPEN
            && $cart->paymentmethod eq 'gco'
            && $cart->total_cash == $form->{'order-total'};

        $dbh->do(
            q{INSERT INTO gco_map (gcoid, cartid, email, contactname)
              VALUES (?, ?, ?, ?)},
            undef, $gon, $cart->id, $form->{'buyer-billing-address.email'},
            $form->{'buyer-billing-address.contact-name'}
        );
        die "failed to update gco_map: " . $dbh->errstr . "\n"
            if $dbh->err;

        # we need to actually charge the order now ...
        my $eng = $class->new_from_gcoid($gon)
            or die "failed to load engine for Google Order Number $gon\n";
        $eng->charge_order;

        # if we actually captured some money, then we need to make sure that the order
        # gets to be marked as ready to go
    }
    elsif ( $form->{_type} eq 'charge-amount-notification' ) {
        my $eng = $class->new_from_gcoid($gon)
            or die "failed to load engine for Google Order Number $gon\n";

        # sanity check again, make sure our cart still looks good
        return 1
            unless $eng->cart->state == $DW::Shop::STATE_PEND_PAID
            && $eng->cart->paymentmethod eq 'gco'
            && $eng->cart->total_cash == $form->{'total-charge-amount'};

        # looks good, mark it paid so it gets processed
        $eng->cart->state($DW::Shop::STATE_PAID);

        # NOTE: do not send an email here.  Google requests that people who implement
        # Google Checkout do not actually send a confirmation email, as they will
        # take care of that when the user places the order, and one email should be
        # enough for most purposes.
    }
}

# accessors
sub gcoid       { $_[0]->{gcoid} }
sub cart        { $_[0]->{cart} }
sub contactname { $_[0]->{contactname} }
sub email       { $_[0]->{email} }

# returns a Google Checkout object with our proper server configuration
sub gco {
    return Google::Checkout::General::GCO->new(
        config_path => "$LJ::HOME/etc/google-checkout.conf" );
}

1;
