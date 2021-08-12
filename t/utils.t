# t/utils.t
#
# Test LJ::Utils module
#
# Authors:
#      Martin DeMello <martindemello@gmail.com>
#
# Copyright (c) 2021 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More tests => 6;

use Scalar::Util;

BEGIN { require "$ENV{LJHOME}/t/lib/ljtestlib.pl"; }
use LJ::Utils;

is( length( LJ::rand_chars(0) ),  0 );
is( length( LJ::rand_chars(1) ),  1 );
is( length( LJ::rand_chars(10) ), 10 );

my $m = LJ::md5_struct("hello");
is( $m->hexdigest, "5d41402abc4b2a76b9719d911017c592" );

my $rand_int = LJ::urandom_int();
ok( Scalar::Util::looks_like_number($rand_int) );

is( length( LJ::urandom( size => 10 ) ), 10 );
