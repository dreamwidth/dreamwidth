# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

my $k;

$k = LJ::Knob->instance("test_knob");
ok($k);

$k->set_value(50);
is($k->value, 50, "knob value is 50");

my ($match, $nomatch);
for (1..500) {
    if ($k->check($_)) {
        $match++;
        die "inconsistent" unless $k->check($_);
    } else {
        $nomatch++;
        die "inconsistent" if $k->check($_);
    }
}
is($match, 269, "269 matched");
is($nomatch, 231, "231 didn't match");
