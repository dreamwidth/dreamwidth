#!/usr/bin/perl
#
# t/shop-cart.t
#
# Cart testing code.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2019 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw (temp_user);

use DW::Shop::Cart;

plan tests => 7;

my $u1 = temp_user();

# workaround: new_cart breaks if no uniq
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = LJ::UniqCookie->generate_uniq_ident;
local $LJ::T_SUPPRESS_EMAIL           = 1;

my $error;

my $cart = DW::Shop::Cart->new_cart($u1);
ok( $cart, 'created new cart' );

# Test metadata
ok( $cart->paymentmethod_metadata( test => 1 ) == 1 );
ok( $cart->paymentmethod_metadata('test') == 1 );
ok( !defined $cart->paymentmethod_metadata('test2') );

# Test reloading
my $cart2 = DW::Shop::Cart->get_from_cartid( $cart->id );
ok( $cart2->id == $cart->id );
ok( $cart2->paymentmethod_metadata('test') == 1 );
ok( !defined $cart2->paymentmethod_metadata('test2') );
