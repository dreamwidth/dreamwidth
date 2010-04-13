# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::CProd;
use LJ::Test qw(memcache_stress temp_user);

if ( @LJ::CPROD_PROMOS ) {
    plan tests => 4;
} else {
    plan skip_all => '@LJ::CPROD_PROMOS undefined.';
}

sub run_tests {
    my $u = temp_user();

    my $class = LJ::CProd->prod_to_show($u);
    ok($class, "Got prod to show");

    # mark acked and nothanks and check accessors
    LJ::CProd->mark_acked($u, $class);
    ok($class->has_acked($u), "Marked acked");

    $class = LJ::CProd->prod_to_show($u);
    ok($class, "Got prod to show");

    LJ::CProd->mark_dontshow($u, $class);
    ok($class->has_dismissed($u), "Marked dontshow");
}

memcache_stress(\&run_tests);
