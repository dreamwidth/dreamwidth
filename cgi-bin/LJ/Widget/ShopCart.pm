#!/usr/bin/perl
#
# LJ::Widget::ShopCart
#
# Returns the current shopping cart for the remote user.
#
# Authors:
#      Janine Smith <janine@netrophic.com>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Widget::ShopCart;

use strict;
use base qw/ LJ::Widget /;
use Carp qw/ croak /;

use DW::Shop;

sub need_res { qw( stc/shop.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    my $ret;

    my $cart = $opts{cart} ||= DW::Shop->get->cart
        or return $class->ml('widget.shopcart.error.nocart');

    return $class->ml('widget.shopcart.error.noitems')
        unless $cart->has_items;

    # if the cart is not in state OPEN, mark this as a receipt load
    # no matter where we are
    $opts{receipt} = 1
        unless $cart->state == $DW::Shop::STATE_OPEN;
    $opts{receipt} = 1
        if $opts{admin};
    $opts{receipt} = 1
        if $opts{confirm};

    # if we're not doing a receipt load, then we should balance the points.  this
    # fixes situations where the user gets gifted points while they're shopping.
    unless ( $opts{receipt} ) {
        $cart->recalculate_costs;
        $cart->save;
    }

    my $colspan = $opts{receipt} ? 5 : 6;

    $ret .= $class->start_form
        unless $opts{receipt};

    $ret .= "<table class='shop-cart grid'>";
    $ret .= "<thead>";
    $ret .= "<tr><th></th>"
        unless $opts{receipt};
    $ret .= "<th>" . $class->ml('widget.shopcart.header.item') . "</th>";
    $ret .= "<th>" . $class->ml('widget.shopcart.header.deliverydate') . "</th>";
    $ret .= "<th>" . $class->ml('widget.shopcart.header.to') . "</th>";
    $ret .= "<th>" . $class->ml('widget.shopcart.header.from') . "</th>";
    $ret .= "<th>" . $class->ml('widget.shopcart.header.random') . "</th>" if $opts{admin};
    $ret .= "<th>" . $class->ml('widget.shopcart.header.price') . "</th>";
    $ret .= "<th>ADMIN</th>" if $opts{admin};
    $ret .= "</tr>";
    $ret .= "</thead>";

    $ret .= "<tfoot>";
    my $buttons = '&nbsp;';
    unless ( $opts{receipt} ) {
        $buttons = $class->html_submit(
            removeselected => $class->ml('widget.shopcart.btn.removeselected') )
            . " "
            . $class->html_submit( discard => $class->ml('widget.shopcart.btn.discard') ) . "</p>";
    }
    $ret .=
"<tr><td class='total' style='border-right: none; text-align: left;' colspan='3'>$buttons</td>";
    $ret .=
          "<td style='border-left: none;' colspan='"
        . ( $colspan - 3 )
        . "' class='total'>"
        . $class->ml('widget.shopcart.total') . " "
        . $cart->display_total
        . "</td></tr>";
    $ret .= "</tfoot>";

    $ret .= "<tbody>";
    foreach my $item ( @{ $cart->items } ) {
        $ret .= "<tr>";
        if ( $opts{receipt} ) {

            # empty column for receipt
        }
        elsif ( $item->noremove ) {
            $ret .= "<td></td>";
        }
        else {
            $ret .=
                "<td>" . $class->html_check( name => 'remove_' . $item->id, value => 1 ) . "</td>";
        }

        $ret .= "<td>" . $item->name_html;
        $ret .= "<p class='note'>" . $item->note . "</p>" if $item->note;
        $ret .= "</td>";

        $ret .= "<td>"
            . (
              $item->deliverydate
            ? $item->deliverydate
            : $class->ml('widget.shopcart.deliverydate.asap')
            ) . "</td>";
        $ret .= "<td>" . $item->t_html( admin => $opts{admin} ) . "</td>";
        $ret .= "<td>" . $item->from_html . "</td>";
        $ret .= "<td>" . ( ref $item =~ /Account/ && $item->random ? 'Y' : 'N' ) . "</td>"
            if $opts{admin};
        $ret .= "<td>" . $item->display_paid . "</td>\n";

        if ( $opts{admin} ) {
            $ret .= "<td>";
            if ( $item->t_email ) {
                my $dbh  = LJ::get_db_writer();
                my $acid = $dbh->selectrow_array(
                    'SELECT acid FROM shop_codes WHERE cartid = ? AND itemid = ?',
                    undef, $cart->id, $item->id );
                if ($acid) {
                    my ( $auth, $rcptid ) =
                        $dbh->selectrow_array( 'SELECT auth, rcptid FROM acctcode WHERE acid = ?',
                        undef, $acid );
                    $ret .= DW::InviteCodes->encode( $acid, $auth );
                    if ( my $ru = LJ::load_userid($rcptid) ) {
                        $ret .= ' ('
                            . $ru->ljuser_display
                            . ", <a href='$LJ::SITEROOT/admin/pay/index?view="
                            . $ru->user
                            . "'>edit</a>)";
                    }
                    else {
                        $ret .=
" (unused, <a href='$LJ::SITEROOT/admin/pay/view?striptimefrom=$acid'>strip</a>)";
                    }
                }
                else {
                    $ret .= 'no code yet or code was stripped';
                }
            }
            else {
                $ret .= '--';
            }
            $ret .= "</td>";
        }
        $ret .= "</tr>";
    }
    $ret .= "</tbody>";

    $ret .= "</table>";

    unless ( $opts{receipt} ) {
        $ret .=
              "<div class='shop-cart-btn'><p><strong>"
            . $class->ml('widget.shopcart.paymentmethod')
            . "</strong> ";

        # if the cart is zero cost, then we can just let them check out
        if ( $cart->total_cash == 0.00 ) {
            $ret .= $class->html_submit(
                checkout_free => $class->ml('widget.shopcart.paymentmethod.free') );

        }
        else {
            # google has very specific rules about where the buttons go and how to display them
            # ... so we have to abide by that
            if ( LJ::is_enabled('googlecheckout') ) {
                $ret .=
                      '<input type="image" name="'
                    . $class->input_prefix
                    . '_checkout_gco" src="https://checkout.google.com/buttons/checkout.gif?'
                    . 'merchant_id=&w=180&h=46&style=trans&variant=text&loc=en_US" alt="Use Google Checkout" style="vertical-align: middle;" /> or use ';
                $ret .= " &nbsp;&nbsp;";
            }

            # and now any hooks that want to add to this...
            $ret .= $class->html_submit(
                checkout_creditcard => $class->ml('widget.shopcart.paymentmethod.creditcard') );
            $ret .= " &nbsp;&nbsp;";

            # check or money order button
            $ret .= $class->html_submit(
                checkout_cmo => $class->ml('widget.shopcart.paymentmethod.checkmoneyorder') );
        }

        $ret .= "</p></div>";
        $ret .= $class->end_form;
    }

    # allow hooks to alter the cart or append to it
    LJ::Hooks::run_hooks( 'shop_cart_render', \$ret, %opts );

    return $ret;
}

sub handle_post {
    my ( $class, $post, %opts ) = @_;

    # checkout methods depend on which button was clicked
    my $cm;
    $cm = 'gco'
        if LJ::is_enabled('googlecheckout')
        && ( $post->{checkout_gco} || $post->{'checkout_gco.x'} );
    $cm = 'creditcard'      if $post->{checkout_creditcard};
    $cm = 'checkmoneyorder' if $post->{checkout_cmo} || $post->{checkout_free};

    # check out?
    return BML::redirect("$LJ::SITEROOT/shop/checkout?method=$cm")
        if defined $cm;

    # remove selected items
    if ( $post->{removeselected} ) {
        my $cart = DW::Shop->get->cart
            or return ( error => $class->ml('widget.shopcart.error.nocart') );

        foreach my $val ( keys %$post ) {
            next unless $post->{$val} && $val =~ /^remove_(\d+)$/;
            $cart->remove_item($1);
        }
    }

    # discard entire cart
    if ( $post->{discard} ) {
        return BML::redirect("$LJ::SITEROOT/shop?newcart=1");
    }

    return;
}

1;
