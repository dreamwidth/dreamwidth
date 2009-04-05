#!/usr/bin/perl
#
# DW::Widget::ShopCartStatusBar
#
# Renders the status bar used to show someone's status in the shop.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Widget::ShopCartStatusBar;

use strict;
use base qw/ LJ::Widget /;
use Carp qw/ croak /;

use DW::Shop;

# general purpose shop CSS used by the entire shop system
sub need_res { qw( stc/widgets/shop.css ) }

# main renderer for this particular thingy
sub render_body {
    my ( $class, %opts ) = @_;

    # make sure the shop is initialized
    my $shop = DW::Shop->get;
    my $u = $shop->u;

    # if they want a new cart, give them one; this is immediate and the
    # old cart is gone with the wind ...
    my $cart = $opts{newcart} ? DW::Shop::Cart->new_cart( $u ) : $shop->cart;

    # if minimal, and the cart is empty, bail
    return if $opts{minimal} && ! $cart->has_items;

    # render out information about this cart
    my $ret = '[ ';
    $ret .= 'Shopping Cart for ' . ( $u ? $u->ljuser_display : 'anonymous user' );
    $ret .= '; cartid = ' . $cart->id;
    $ret .= ' created ' . LJ::ago_text( $cart->age );
    $ret .= '; total = $' . $cart->display_total;
    $ret .= '; <a href="/shop?newcart=1">make new cart</a>';
    $ret .= '; <a href="/shop/cart">view cart</a>';
    $ret .= '; <a href="/shop/checkout">checkout</a>';
    $ret .= ' ]';

    return $ret;
}

1;
