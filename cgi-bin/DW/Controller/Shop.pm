#!/usr/bin/perl
#
# DW::Controller::Shop
#
# This controller is for shop handlers.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2010-2018 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Shop;

use strict;
use warnings;
use Carp qw/ croak confess /;

use DW::Controller;
use DW::Pay;
use DW::Routing;
use DW::Shop;
use DW::Template;
use LJ::JSON;

# routing directions
DW::Routing->register_string( '/shop',          \&shop_index_handler,    app => 1 );
DW::Routing->register_string( '/shop/receipt',  \&shop_receipt_handler,  app => 1 );
DW::Routing->register_string( '/shop/checkout', \&shop_checkout_handler, app => 1 );
DW::Routing->register_string( '/shop/history',  \&shop_history_handler,  app => 1 );
DW::Routing->register_string( '/shop/cancel',   \&shop_cancel_handler,   app => 1 );
DW::Routing->register_string( '/shop/cart',     \&shop_cart_handler,     app => 1 );
DW::Routing->register_string( '/shop/confirm',  \&shop_confirm_handler,  app => 1 );

# our basic shop controller, this does setup that is unique to all shop
# pages and everybody should call this first.  returns the same tuple as
# the controller method.
sub _shop_controller {
    my %args = (@_);
    my $r    = DW::Request->get;

    # if payments are disabled, do nothing
    unless ( LJ::is_enabled('payments') ) {
        return ( 0, error_ml('shop.unavailable') );
    }

    # if they're banned ...
    if ( my $err = DW::Shop->remote_sysban_check ) {
        return ( 0, DW::Template->render_template( 'error.tt', { message => $err } ) );
    }

    # if they aren't on the shop domain, redirect
    if ( $LJ::DOMAIN_SHOP && $r->host ne $LJ::DOMAIN_SHOP ) {
        return ( 0, $r->redirect("$LJ::SHOPROOT/") );
    }

    # basic controller setup
    my ( $ok, $rv ) = controller(%args);
    return ( $ok, $rv ) unless $ok;

    # the entire shop uses these files
    LJ::need_res('stc/shop.css');
    LJ::set_active_resource_group('foundation');

    # figure out what shop/cart to use
    $rv->{shop} = DW::Shop->get;
    $rv->{cart} =
        $r->get_args->{newcart} ? DW::Shop::Cart->new_cart( $rv->{u} ) : $rv->{shop}->cart;
    $rv->{cart} =
        $r->get_args->{ordernum}
        ? DW::Shop::Cart->get_from_ordernum( $r->get_args->{ordernum} )
        : $rv->{shop}->cart;

    # populate vars with cart display template
    $rv->{cart_display} = DW::Template->template_string( 'shop/cartdisplay.tt', $rv );

    # call any hooks to do things before we return success
    LJ::Hooks::run_hooks( 'shop_controller', $rv );

    return ( 1, $rv );
}

# handles the shop index page
sub shop_index_handler {
    my ( $ok, $rv ) = _shop_controller( anonymous => 1 );
    return $rv unless $ok;

    $rv->{shop_config} = \%LJ::SHOP;

    return DW::Template->render_template( 'shop/index.tt', $rv );
}

# view the receipt for a specific order
sub shop_receipt_handler {

    # this doesn't do form handling or state changes, don't need full shop_controller
    my $r = DW::Request->get;
    return $r->redirect("$LJ::SITEROOT/") unless LJ::is_enabled('payments');

    if ( my $err = DW::Shop->remote_sysban_check ) {
        return DW::Template->render_template( 'error.tt', { message => $err } );
    }

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $args  = $r->get_args;
    my $scope = '/shop/receipt.tt';

    # we don't have to be logged in, but we do need an ordernum passed in
    my $ordernum = $args->{ordernum} // '';

    my $cart = DW::Shop::Cart->get_from_ordernum($ordernum);
    return error_ml("$scope.error.invalidordernum") unless $cart;

    # cart cannot be in open, closed, or checkout state
    my %invalid_state = (
        $DW::Shop::STATE_OPEN     => 1,
        $DW::Shop::STATE_CLOSED   => 1,
        $DW::Shop::STATE_CHECKOUT => 1,
    );
    return $r->redirect("$LJ::SHOPROOT/cart") if $invalid_state{ $cart->state };

    # set up variables for template
    my $vars = { cart => $cart };

    $vars->{orderdate} = DateTime->from_epoch( epoch => $cart->starttime );
    $vars->{carttable} = LJ::Widget::ShopCart->render( receipt => 1, cart => $cart );

    return DW::Template->render_template( 'shop/receipt.tt', $vars );
}

# handles the shop checkout page
sub shop_checkout_handler {
    my ( $ok, $rv ) = _shop_controller( anonymous => 1 );
    return $rv unless $ok;

    my $cart  = $rv->{cart};
    my $r     = DW::Request->get;
    my $GET   = $r->get_args;
    my $scope = 'shop/checkout.tt';

    return error_ml("$scope.error.nocart") unless $cart;
    return error_ml("$scope.error.emptycart") unless $cart->has_items;

    # FIXME: if they have a $0 cart, we don't support that yet
    return error_ml("$scope.error.zerocart")
        if $cart->total_cash == 0.00 && $cart->total_points == 0;

    # establish the engine they're trying to use
    my $eng = DW::Shop::Engine->get( $GET->{method}, $cart );
    return error_ml("$scope.error.invalidpaymentmethod")
        unless $eng;

    # set the payment method on the cart
    $cart->paymentmethod( $GET->{method} );

    # redirect to checkout url
    my $url = $eng->checkout_url;
    return $eng->errstr
        unless $url;
    return $r->redirect($url);

}

sub shop_history_handler {
    my ( $ok, $rv ) = _shop_controller();
    return $rv unless $ok;

    my $cart   = $rv->{cart};
    my $r      = DW::Request->get;
    my $remote = $rv->{remote};

    my @carts = DW::Shop::Cart->get_all( $remote, finished => 1 );
    foreach my $cart (@carts) {
        $cart->{date} = DateTime->from_epoch( epoch => $cart->starttime );
    }

    return DW::Template->render_template( 'shop/history.tt', { carts => \@carts } );
}

# handles the shop cancel page
sub shop_cancel_handler {
    my ( $ok, $rv ) = _shop_controller( anonymous => 1 );
    return $rv unless $ok;

    my $r     = DW::Request->get;
    my $GET   = $r->get_args;
    my $scope = 'shop/cancel.tt';

    my ( $ordernum, $token, $payerid ) = ( $GET->{ordernum}, $GET->{token}, $GET->{PayerID} );
    my ( $cart, $eng );

    # use ordernum if we have it, otherwise use token/payerid
    if ($ordernum) {
        $cart = DW::Shop::Cart->get_from_ordernum($ordernum);
        return error_ml("$scope.error.invalidordernum")
            unless $cart;

        my $paymentmethod = $cart->paymentmethod;
        my $paymentmethod_class =
            'DW::Shop::Engine::' . $DW::Shop::PAYMENTMETHODS{$paymentmethod}->{class};
        $eng = $paymentmethod_class->new_from_cart($cart);
        return error_ml("$scope.error.invalidcart")
            unless $eng;
    }
    else {
        return error_ml("$scope'.error.needtoken")
            unless $token;

        # we can assume paypal is the engine if we have a token
        $eng = DW::Shop::Engine::PayPal->new_from_token($token);
        return error_ml("$scope'.error.invalidtoken")
            unless $eng;

        $cart     = $eng->cart;
        $ordernum = $cart->ordernum;
    }

    # cart must be in open state
    return $r->redirect("$LJ::SHOPROOT/receipt?ordernum=$ordernum")
        unless $cart->state == $DW::Shop::STATE_OPEN;

    # cancel payment and discard cart
    if ( $eng->cancel_order ) {
        return $r->redirect("$LJ::SHOPROOT?newcart=1");
    }

    return error_ml("$scope.error.cantcancel");

}

# Allows for viewing and manipulating the shopping cart.
sub shop_cart_handler {
    my ( $ok, $rv ) = _shop_controller( anonymous => 1 );
    return $rv unless $ok;

    my $cart   = $rv->{cart};
    my $r      = DW::Request->get;
    my $remote = $rv->{remote};
    my $GET    = $r->get_args;
    my $POST   = $r->post_args;

    if ( $r->did_post() ) {

        # checkout methods depend on which button was clicked
        my $cm;
        $cm = 'checkmoneyorder' if $POST->{checkout_cmo} || $POST->{checkout_free};
        $cm = 'stripe'          if $POST->{checkout_stripe};

        # check out?
        return $r->redirect("$LJ::SHOPROOT/checkout?method=$cm")
            if defined $cm;

        # remove selected items
        if ( $POST->{'removeselected'} ) {
            return error_ml('widget.shopcart.error.nocart') unless $cart;

            foreach my $val ( keys %$POST ) {
                next unless $POST->{$val} && $val =~ /^remove_(\d+)$/;
                $cart->remove_item($1);
            }
        }

        # discard entire cart
        if ( $POST->{'discard'} ) {
            return $r->redirect("$LJ::SHOPROOT?newcart=1");
        }

    }

    my $vars = {
        duplicate   => $GET->{duplicate},
        failed      => $GET->{failed},
        cart_widget => LJ::Widget::ShopCart->render
    };

    return DW::Template->render_template( 'shop/cart.tt', $vars );
}

# The page used to confirm a user's order before we finally bill them.
sub shop_confirm_handler {
    my ( $ok, $rv ) = _shop_controller( anonymous => 1 );
    return $rv unless $ok;

    my $r      = DW::Request->get;
    my $remote = $rv->{remote};
    my $GET    = $r->get_args;
    my $POST   = $r->post_args;
    my $vars;

    my $scope = "/shop/confirm.tt";

    my ( $ordernum, $token, $payerid ) = ( $GET->{ordernum}, $GET->{token}, $GET->{PayerID} );
    my ( $cart, $eng, $paymentmethod );

    # use ordernum if we have it, otherwise use token/payerid
    if ($ordernum) {
        $cart = DW::Shop::Cart->get_from_ordernum($ordernum);
        return error_ml("$scope.error.invalidordernum")
            unless $cart;

        $paymentmethod = $cart->paymentmethod;
        my $paymentmethod_class =
            'DW::Shop::Engine::' . $DW::Shop::PAYMENTMETHODS{$paymentmethod}->{class};
        $eng = $paymentmethod_class->new_from_cart($cart);
        return error_ml("$scope.error.invalidcart")
            unless $eng;
    }
    else {
        return error_ml("$scope.error.needtoken")
            unless $token;

        # we can assume paypal is the engine if we have a token
        $eng = DW::Shop::Engine::PayPal->new_from_token($token);
        return error_ml("$scope.error.invalidtoken")
            unless $eng;

        $cart          = $eng->cart;
        $ordernum      = $cart->ordernum;
        $paymentmethod = $cart->paymentmethod;
    }

    # cart must be in open/checkout state
    return $r->redirect("$LJ::SHOPROOT/receipt?ordernum=$ordernum")
        unless $cart->state == $DW::Shop::STATE_OPEN || $cart->state == $DW::Shop::STATE_CHECKOUT;

    # check email early so we can re-render the form on error
    my ( $email_checkbox, @email_errors );
    if ( $r->did_post && !$cart->userid ) {
        LJ::check_email( $POST->{email}, \@email_errors, $POST, \$email_checkbox );
    }

    if ( $r->did_post && !@email_errors ) {
        if ( $cart->userid ) {
            my $u = LJ::load_userid( $cart->userid );
            $cart->email( $u->email_raw );
        }
        else {
            # email checked above
            $cart->email( $POST->{email} );
        }

        # and now set the state, we're waiting for the user to send us money
        $cart->state($DW::Shop::STATE_CHECKOUT);

        # they want to pay us, yippee!
        my $confirm = $eng->confirm_order;
        return $eng->errstr
            unless $confirm;
        $vars->{confirm} = $confirm;

    }

    if ( !$r->did_post() || @email_errors ) {

        # set the payerid for later
        $eng->payerid($payerid)
            if $payerid;
    }

    $vars->{showform}      = ( !$r->did_post || @email_errors );
    $vars->{email_errors}  = \@email_errors;
    $vars->{cart}          = $cart;
    $vars->{ordernum}      = $ordernum;
    $vars->{email}         = $POST->{email};
    $vars->{widget}        = LJ::Widget::ShopCart->render( confirm => 1, cart => $cart );
    $vars->{paymentmethod} = $paymentmethod;

    return DW::Template->render_template( 'shop/confirm.tt', $vars );
}

1;
