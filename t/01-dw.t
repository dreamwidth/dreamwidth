#!/usr/bin/perl -w
use strict;

use Test::More;
plan tests => 3;

use lib "$ENV{LJHOME}/cgi-bin";

use_ok('DW');

my $dir = DW->home;

ok($dir, 'DW->home returns something');
ok(-d $dir, 'DW->home returns a directory');

