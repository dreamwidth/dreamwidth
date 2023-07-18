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
    my $cart = $opts{cart} ||= DW::Shop->get->cart
        or return $class->ml('widget.shopcart.error.nocart');

    return $class->ml('widget.shopcart.error.noitems')
        unless $cart->has_items;

    my $receipt = $opts{receipt};

    # if the cart is not in state OPEN, mark this as a receipt load
    # no matter where we are
    $receipt = 1
        unless $cart->state == $DW::Shop::STATE_OPEN;
    $receipt = 1
        if $opts{admin};
    $receipt = 1
        if $opts{confirm};

    # if we're not doing a receipt load, then we should balance the points.  this
    # fixes situations where the user gets gifted points while they're shopping.
    unless ($receipt) {
        $cart->recalculate_costs;
        $cart->save;
    }

    my $colspan = $opts{receipt} ? 5 : 6;

    my $vars = {
        receipt => $receipt,
        confirm => $opts{confirm},
        admin   => $opts{admin},
        colspan => ( $colspan - 3 ),
        cart    => $cart
    };

    $vars->{admin_col} = sub {
        my $item = $_;
        my $ret;
        my $dbh = LJ::get_db_writer();
        my $acid =
            $dbh->selectrow_array( 'SELECT acid FROM shop_codes WHERE cartid = ? AND itemid = ?',
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
                    " (unused, <a href='$LJ::SITEROOT/admin/pay/striptime?from=$acid'>strip</a>)";
            }
        }
        else {
            $ret .= 'no code yet or code was stripped';
        }
        return $ret;
    };

    $vars->{is_random} = sub { return ref $_ =~ /Account/ && $_->random ? 'Y' : 'N'; };

    my $checkout_ready =
        !$opts{receipt} || ( !$opts{confirm} && $cart->state == $DW::Shop::STATE_CHECKOUT );
    if ($checkout_ready) {

        # check or money order button
        my $cmo_threshold =
            $LJ::SHOP_CMO_MINIMUM ? $cart->total_cash - $LJ::SHOP_CMO_MINIMUM : undef;
        $vars->{disable_cmo}    = defined $cmo_threshold ? $cmo_threshold < 0 : 0;
        $vars->{cc_avail}       = $LJ::STRIPE{enabled};
        $vars->{cmo_avail}      = LJ::is_enabled('payments_cmo');
        $vars->{gco_avail}      = LJ::is_enabled('googlecheckout');
        $vars->{checkout_ready} = $checkout_ready;
        $vars->{cmo_min}        = sprintf( '$%0.2f USD', $LJ::SHOP_CMO_MINIMUM );
    }

    my $ret = DW::Template->template_string( 'widget/shopcart.tt', $vars );

    # allow hooks to alter the cart or append to it
    LJ::Hooks::run_hooks( 'shop_cart_render', \$ret, %opts );

    return $ret;
}

1;
