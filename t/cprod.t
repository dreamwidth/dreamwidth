# t/cprod.t
#
# Test to TODO
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

use Test::More;

use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { require 'ljlib.pl'; }
use LJ::CProd;
use LJ::Test qw(memcache_stress temp_user);

if ( @LJ::CPROD_PROMOS ) {
    plan tests => 4;
} else {
    plan skip_all => '@LJ::CPROD_PROMOS undefined.';
}

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
