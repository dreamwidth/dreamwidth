#!/usr/bin/perl
#
# DW::Shop::Engine
#
# Simple interface to a payment engine.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Shop::Engine;

use strict;
use DW::Shop::Engine::CheckMoneyOrder;
use DW::Shop::Engine::CreditCardPP;
use DW::Shop::Engine::PayPal;
use DW::Shop::Engine::GoogleCheckout;
use DW::Shop::Engine::CreditCard;

# get( $method, $cart )
#
# returns the proper subclass for the given payment method, if one exists
sub get {
    return DW::Shop::Engine::PayPal->new( $_[2] )          if $_[1] eq 'paypal';
    return DW::Shop::Engine::GoogleCheckout->new( $_[2] )  if $_[1] eq 'gco';
    return DW::Shop::Engine::CreditCardPP->new( $_[2] )    if $_[1] eq 'creditcardpp';
    return DW::Shop::Engine::CheckMoneyOrder->new( $_[2] ) if $_[1] eq 'checkmoneyorder';
    return DW::Shop::Engine::CreditCard->new( $_[2] )      if $_[1] eq 'creditcard';

    warn "Payment method '$_[1]' not supported.\n";
    return undef;
}

# temp_error( $str )
#
# returns undef and sets an error string
sub temp_error {
    my ( $self, $err, %msg ) = @_;

    $self->{errmsg}  = LJ::Lang::ml( "error.pay.$err", \%msg ) || $err;
    $self->{errtemp} = 1;
    return undef;
}

# error( $ml_str )
#
# returns permanent error.
sub error {
    my ( $self, $err, %msg ) = @_;

    $self->{errmsg}  = LJ::Lang::ml( "error.pay.$err", \%msg ) || $err;
    $self->{errtemp} = 0;
    return undef;
}

# errstr()
#
# returns the text of the last error
sub errstr {
    return $_[0]->{errmsg};
}

# err()
#
# returns 1/0 if we had an error
sub err {
    return defined $_[0]->{errtemp} ? 1 : 0;
}

# err_is_temporary()
#
# returns 1/0 if the error is classified as temporary and you should retry,
# also returns undef if no error has occurred.
sub err_is_temporary {
    return $_[0]->{errtemp};
}

# fail_transaction()
#
# this is a 'something bad has happened, consider this cart and transaction
# to be dead' sort of thing
sub fail_transaction {
    die "Please implement $_[0]" . "->fail_transaction.\n";
}

# called when someone wants us to try to capture the points
# FIXME: should move the 'cart' accessor and logic up to this base class ...
sub try_capture_points {
    my $self = $_[0];

    # if the order costs no points, we're done and successful
    return 1 unless $self->cart->total_points > 0;

    # else, we need to try to capture them
    my $u = LJ::load_userid( $self->cart->userid )
        or die "Failed to load user to deduct points from.\n";
    $u->give_shop_points(
        amount => -$self->cart->total_points,
        reason => sprintf( 'order %d confirmed', $self->cart->id )
    ) or die "Failed to deduct points from account.\n";

    # we're a happy clam
    return 1;
}

# called to give back the points that we took from the user in case another
# part of the transaction has failed
sub refund_captured_points {
    my $self = $_[0];

    # if the order costs no points, we're done and successful
    return 1 unless $self->cart->total_points > 0;

    # else, we need to try to capture them
    my $u = LJ::load_userid( $self->cart->userid )
        or die "Failed to load user to restore points to; contact site administrators.\n";
    $u->give_shop_points(
        amount => $self->cart->total_points,
        reason => sprintf( 'order %d failed', $self->cart->id )
    ) or die "Failed to add points to account.\n";

    # we're a happy clam
    return 1;
}

1;
