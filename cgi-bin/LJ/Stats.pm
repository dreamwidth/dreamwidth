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

# This is a module for returning stats info
# Functions in statslib.pl should get moved here

use strict;

package LJ::Stats;

sub get_popular_interests {
    my $memkey = 'pop_interests';
    my $ints;

    # Try to fetch from memcache
    my $mem = LJ::MemCache::get($memkey);
    if ($mem) {
        $ints = $mem;
        return $ints;
    }

    # Fetch from database
    my $dbr = LJ::get_db_reader();
    $ints = $dbr->selectall_arrayref("SELECT statkey, statval FROM stats WHERE ".
        "statcat=? ORDER BY statval DESC, statkey ASC", undef, 'pop_interests');
    return undef if $dbr->err;

    # update memcache
    my $rv = LJ::MemCache::set($memkey, \@$ints, 3600);

    return $ints;
}

1;
