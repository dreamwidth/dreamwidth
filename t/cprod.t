# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::CProd;
use LJ::Test qw(memcache_stress temp_user);


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
