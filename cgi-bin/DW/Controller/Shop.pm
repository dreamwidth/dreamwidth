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
DW::Routing->register_string( '/shop',         \&shop_index_handler,   app => 1 );
DW::Routing->register_string( '/shop/receipt', \&shop_receipt_handler, app => 1 );

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

    # basic controller setup
    my ( $ok, $rv ) = controller(%args);
    return ( $ok, $rv ) unless $ok;

    # the entire shop uses these files
    LJ::need_res('stc/shop.css');
    LJ::set_active_resource_group('jquery');

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
    return $r->redirect("$LJ::SITEROOT/shop/cart") if $invalid_state{ $cart->state };

    # set up variables for template
    my $vars = { cart => $cart };

    $vars->{orderdate} = DateTime->from_epoch( epoch => $cart->starttime );
    $vars->{carttable} = LJ::Widget::ShopCart->render( receipt => 1, cart => $cart );

    return DW::Template->render_template( 'shop/receipt.tt', $vars );
}

1;
