#!/usr/bin/perl
#
# DW::Widget::ShopCartStatusBar
#
# Renders the status bar used to show someone's status in the shop.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Janine Smith <janine@netrophic.com>
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

sub need_res { qw( stc/shop.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    # make sure the shop is initialized
    my $shop = DW::Shop->get;
    my $u    = $shop->u;

    # if they want a new cart, give them one; this is immediate and the
    # old cart is gone with the wind ...
    my $cart = $opts{newcart} ? DW::Shop::Cart->new_cart($u) : $shop->cart;

    # render out information about this cart
    my $ret;
    if ( $cart->has_items ) {
        $ret .= "<div class='shop-cart-status highlight-box'>";
        $ret .= "<strong>" . $class->ml('widget.shopcartstatusbar.header') . "</strong><br />";
        $ret .= $class->ml( 'widget.shopcartstatusbar.itemcount',
            { num => $cart->num_items, price => $cart->display_total } );
        $ret .= "<br />";

        $ret .= "<ul>";
        $ret .=
              "<li><a href='$LJ::SITEROOT/shop/cart'><strong>"
            . $class->ml('widget.shopcartstatusbar.viewcart')
            . "</strong></a></li>";
        $ret .=
              "<li><a href='$LJ::SITEROOT/shop?newcart=1'><strong>"
            . $class->ml('widget.shopcartstatusbar.newcart')
            . "</strong></a></li>";
        $ret .= "</ul>";

        $ret .= "</div>";
    }

    # call out to hooks to see if they want to munge with the content
    LJ::Hooks::run_hooks( 'shop_cart_status_bar', $shop, $cart, \$ret );

    return $ret;
}

1;
