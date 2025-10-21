#!/usr/bin/perl
#
# DW::Shop::Engine::CreditCardPP
#
# This is a very simple payment method, it generates one of those fancy PayPal
# buttons which the user can use to pay.
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

package DW::Shop::Engine::CreditCardPP;

use strict;
use Carp qw/ croak confess /;
use Digest::MD5 qw/ md5_hex /;
use Storable qw/ nfreeze thaw /;

use base qw/ DW::Shop::Engine /;

# new( $cart )
#
# instantiates a new PayPal engine for the given cart
sub new {
    return bless { cart => $_[1] }, $_[0];
}

# checkout_url()
#
# this is simple, send them to the page for entering their credit card information
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

    # return URL to cc entry
    return "$LJ::SITEROOT/shop/creditcard";
}

# accessors
sub cart { $_[0]->{cart} }

1;
