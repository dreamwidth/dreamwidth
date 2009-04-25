#!/usr/bin/perl
#
# DW::Shop::Engine::CheckMoneyOrder
#
# This engine lets the user pay via check/money order.
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

package DW::Shop::Engine::CheckMoneyOrder;

use strict;
use Carp qw/ croak confess /;
use Storable qw/ nfreeze thaw /;

use base qw/ DW::Shop::Engine /;


# new( $cart )
#
# instantiates a new PayPal engine for the given cart
sub new {
    return bless { cart => $_[1] }, $_[0];
}


# new_from_cart( $cart )
#
# constructs an engine from a given cart.  doesn't really do much
# more than call new() as that's the default
sub new_from_cart {
    return $_[0]->new( $_[1] );
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
    die "Constraints not met: cart && cart->has_items && cart->has_total > 0.00.\n"
        unless $cart && $cart->has_items && $cart->total > 0.00;

    # and, just in case something terrible happens, make sure our state is good
    die "Cart not in valid state!\n"
        unless $cart->state == $DW::Shop::STATE_OPEN;

    # the cart is in a good state, so just send them to the confirmation page which
    # gives them instructions on where to send it
    return "$LJ::SITEROOT/shop/cmo_confirm";
}


# confirm_order()
#
# all this does is mark the order as pending.
sub confirm_order {
    my $self = $_[0];

    # ensure the cart is in checkout state.  if it's still open or paid
    # or something, we can't touch it.
    return $self->error( 'cmo.engbadstate' )
        unless $self->cart->state == $DW::Shop::STATE_CHECKOUT;

    # now set it pending
    $self->cart->state( $DW::Shop::STATE_PEND_PAID );
    return 2;
}


# called when something terrible has happened and we need to fully fail out
# a transaction for some reason.  (payment not valid, etc.)
sub fail_transaction {
    my $self = $_[0];

    # step 1) mark statuses
#    $self->cart->
}


################################################################################
## internal methods, nobody else should be calling these
################################################################################


# accessors
sub cart { $_[0]->{cart} }


1;
