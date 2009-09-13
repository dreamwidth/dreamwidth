# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Lang;

is(LJ::commafy("lalala"), "lalala");
is(LJ::commafy("1"), "1");
is(LJ::commafy("12"), "12");
is(LJ::commafy("123"), "123");
is(LJ::commafy("1234"), "1,234");
is(LJ::commafy("123456"), "123,456");
is(LJ::commafy("1234567"), "1,234,567");


1;

