# -*-perl-*-

use strict;
use Test::More tests => 4;
use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
use LJ::Test qw( temp_user );

{
    my $c;

    $c = eval { LJ::get_cap(undef, 'something_not_defined') };
    is($c, undef, "Undef returns undef");

    $c = eval { LJ::get_cap(undef, 'can_post') };
    is($c, 1, "Undef returns default");


    my $u = temp_user();
    $LJ::T_HAS_ALL_CAPS = 1;
    $c = eval { $u->get_cap( 'anycapatall' ) };
    ok( $c, "Cap always on" );

    $c = eval { $u->get_cap( 'readonly' ) };
    ok( ! $c, "readonly cap is not automatically set enabled" );
}

1;

