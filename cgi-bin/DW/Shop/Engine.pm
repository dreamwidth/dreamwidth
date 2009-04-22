#!/usr/bin/perl
#
# DW::Shop::Engine
#
# Simple interface to a payment engine.
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

package DW::Shop::Engine;

use strict;
use DW::Shop::Engine::PayPal;

# get( $method, $cart )
#
# returns the proper subclass for the given payment method, if one exists
sub get {
    return DW::Shop::Engine::PayPal->new( $_[2] ) if $_[1] eq 'paypal';

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


1;
