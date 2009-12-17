#!/usr/bin/perl
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


package LJ::Syn;
use strict;

sub get_popular_feeds
{
    my $popsyn = LJ::MemCache::get("popsyn");
    unless ($popsyn) {
        $popsyn = _get_feeds_from_db();

        # load u objects so we can get usernames
        my %users;
        LJ::load_userids_multiple([ map { $_, \$users{$_} } map { $_->[0] } @$popsyn ]);
        unshift @$_, $users{$_->[0]}->{'user'}, $users{$_->[0]}->{'name'} foreach @$popsyn;
        # format is: [ user, name, userid, synurl, numreaders ]
        # set in memcache
        my $expire = time() + 3600; # 1 hour
        LJ::MemCache::set("popsyn", $popsyn, $expire);
    }
    return $popsyn;
}

sub get_popular_feed_ids {
    my $popsyn_ids = LJ::MemCache::get("popsyn_ids");
    unless ($popsyn_ids) {
        my $popsyn = _get_feeds_from_db();
        @$popsyn_ids = map { $_->[0] } @$popsyn;

        # set in memcache
        my $expire = time() + 3600; # 1 hour
        LJ::MemCache::set("popsyn_ids", $popsyn_ids, $expire);
    }
    return $popsyn_ids;
}

sub _get_feeds_from_db {
    my $popsyn = [];

    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT userid, synurl, numreaders FROM syndicated ".
                            "WHERE numreaders > 0 ".
                            "AND lastnew > DATE_SUB(NOW(), INTERVAL 14 DAY) ".
                            "ORDER BY numreaders DESC LIMIT 1000");
    $sth->execute();
    while (my @row = $sth->fetchrow_array) {
        push @$popsyn, [ @row ];
    }

    return $popsyn;
}

1;
