# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

ok(Unicode::MapUTF8::utf8_supported_charset("iso-8859-1"), "8859-1 is supported");
ok(Unicode::MapUTF8::utf8_supported_charset("iso-8859-1"), "8859-1 is supported still");
ok(! Unicode::MapUTF8::utf8_supported_charset("iso-8859-gibberish"), "8859-gibberish not supported");
ok(! eval { Unicode::MapUTF8::foobar(); 1; }, "foobar() doesn't exist");
like($@, qr/Unknown subroutine.+foobar/, "and it errored");

is(Unicode::MapUTF8::to_utf8({ -string => "text", -charset => "iso-8859-1" }), "text", "text converted fine");
is(LJ::ConvUTF8->to_utf8("iso-8859-1", "text"), "text", "text converted fine using wrapper");


