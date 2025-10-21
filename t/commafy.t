# t/commafy.t
#
# Test LJ::Commafy module
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
#

use strict;
use warnings;

use Test::More tests => 7;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Lang;

is( LJ::commafy("lalala"),  "lalala" );
is( LJ::commafy("1"),       "1" );
is( LJ::commafy("12"),      "12" );
is( LJ::commafy("123"),     "123" );
is( LJ::commafy("1234"),    "1,234" );
is( LJ::commafy("123456"),  "123,456" );
is( LJ::commafy("1234567"), "1,234,567" );

1;

