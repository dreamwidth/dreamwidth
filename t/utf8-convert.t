# t/utf8-convert.t
#
# Test LJ utf8 conversion
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More tests => 7;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

ok(Unicode::MapUTF8::utf8_supported_charset("iso-8859-1"), "8859-1 is supported");
ok(Unicode::MapUTF8::utf8_supported_charset("iso-8859-1"), "8859-1 is supported still");
ok(! Unicode::MapUTF8::utf8_supported_charset("iso-8859-gibberish"), "8859-gibberish not supported");
ok(! eval { Unicode::MapUTF8::foobar(); 1; }, "foobar() doesn't exist");
like($@, qr/Unknown subroutine.+foobar/, "and it errored");

is(Unicode::MapUTF8::to_utf8({ -string => "text", -charset => "iso-8859-1" }), "text", "text converted fine");
is(LJ::ConvUTF8->to_utf8("iso-8859-1", "text"), "text", "text converted fine using wrapper");


