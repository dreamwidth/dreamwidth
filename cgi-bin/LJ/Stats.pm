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
