# t/currents.t
#
# Test LJ::currents, which assembles the mood/music/location metadata shown on
# an entry. Regression guard: LJ::currents renders the location through
# LJ::Location, but nothing on the render path used to load that module, so the
# eval-wrapped call died silently and the location vanished from every entry.
# This test deliberately does NOT `use LJ::Location` itself -- it must exercise
# the same dependency the render path relies on.
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

use Test::More tests => 4;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Entry;

my %current = LJ::currents(
    {
        current_location => "Testville",
        current_music    => "a song",
        current_mood     => "happy",
    },
    undef
);

is( $current{Location}, "Testville",
    "location renders (LJ::Location is loaded on the render path)" );
is( $current{Music}, "a song", "music renders" );
is( $current{Mood},  "happy",  "mood renders" );

# Coordinates-only entries fall back to the numeric location.
my %coords = LJ::currents( { current_coords => "45.2345,-123.1234" }, undef );
is( $coords{Location}, "45.2345,-123.1234", "coords-only location renders" );
