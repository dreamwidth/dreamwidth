# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Location;

my $loc;

$loc = LJ::Location->new(coords => "45.2345N, 123.1234W");
ok($loc);
is($loc->as_posneg_comma, "45.2345,-123.1234");

$loc = LJ::Location->new(coords => "45.2345N123.1234W");
is($loc->as_posneg_comma, "45.2345,-123.1234");

$loc = LJ::Location->new(coords => "45.2345,-123.1234");
is($loc->as_posneg_comma, "45.2345,-123.1234");

$loc = LJ::Location->new(coords => "45.2345s 123.1234W");
is($loc->as_posneg_comma, "-45.2345,-123.1234");

$loc = eval { LJ::Location->new(coords => "45.2345S -123.1234W"); };
ok(!$loc);
like($@, qr/Invalid coords/);

$loc = eval { LJ::Location->new(coords => "-92.2345 -123.1234"); };
ok(!$loc);
like($@, qr/Lati/);

$loc = eval { LJ::Location->new(coords => "-54.2345 -200.1234"); };
ok(!$loc);
like($@, qr/Longi/);



