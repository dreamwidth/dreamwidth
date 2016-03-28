# t/location.t
#
# Test LJ::Location
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

use Test::More tests => 11;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
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



