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

=head2 C<< LJ::Syn::merge( %opts ) >>

=over

=item Opts:

=over

=item from - Merge from: LJ::User or userid

=item from_name - Merge from username

=item to - Merge to LJ::User or userid

=item to_name - Merge to username

=item url - Merge to URL

=item pretend - Do not actually merge

=back

=back

=cut

sub merge_feed {
    my %args = @_;
    my $from_u;
    if ( $args{from_name} ) {
        $from_u = LJ::load_user( $args{from_name} )
            or return (0, "Invalid user: '" . $args{from_name} . "'.");
    } else {
        $from_u = LJ::want_user( $args{from} )
            or return (0, "Invalid from user.");
    }

    my $to_u;
    if ( $args{to_name} ) {
        $to_u = LJ::load_user( $args{to_name} )
            or return (0, "Invalid user: '" . $args{to_name} . "'.");
    } else {
        $to_u = LJ::want_user( $args{to} )
            or return (0, "Invalid to user.");
    }

    return (0, "Trying to merge into yourself." )
        if $from_u->equals( $to_u );

    # we don't want to unlimit this, so reject if we have too many users
    my @ids = $from_u->watched_by_userids( limit => $LJ::MAX_WT_EDGES_LOAD+1 );
    return (0, "Unable to merge feeds. Too many users are watching the feed '" . $from_u->user . "'. We only allow merges for feeds with at most $LJ::MAX_WT_EDGES_LOAD watchers." )
        if scalar @ids > $LJ::MAX_WT_EDGES_LOAD;

    foreach ($to_u, $from_u) {
        return (0, "Invalid user: '" . $_->user . "' (statusvis is " . $_->statusvis . ", already merged?)")
            unless $_->is_visible;

        return (0, $_->user . " is not a syndicated account.")
            unless $_->is_syndicated;
    }

    my $url = LJ::CleanHTML::canonical_url( $args{url} )
        or return (0, "Invalid URL.");


    return (1,"Everything seems okay") if $args{pretend};

    my $dbh = LJ::get_db_writer();
    my $from_oldurl = $dbh->selectrow_array("SELECT synurl FROM syndicated WHERE userid=?", undef, $from_u->id);
    my $to_oldurl = $dbh->selectrow_array("SELECT synurl FROM syndicated WHERE userid=?", undef, $to_u->id);

    # 1) set up redirection for 'from_user' -> 'to_user'
    $from_u->update_self( { journaltype => 'R', statusvis => 'R' } );
    $from_u->set_prop("renamedto", $to_u->user)
        or return (0,"Unable to set userprop.  Database unavailable?");

    # 2) delete the row in the syndicated table for the user
    #    that is now renamed
    $dbh->do("DELETE FROM syndicated WHERE userid=?",
             undef, $from_u->id);
    return (0,"Database Error: " . $dbh->errstr)
        if $dbh->err;

    # 3) update the url of the destination syndicated account and
    #    tell it to check it now
    $dbh->do("UPDATE syndicated SET synurl=?, checknext=NOW() WHERE userid=?",
             undef, $url, $to_u->id);
    return (0,"Database Error: " . $dbh->errstr)
        if $dbh->err;

    # 4) make users who watch 'from_user' now watch 'to_user'
    # we can't just use delete_ and add_ edges, because we would lose
    # custom group and colors data
    if ( @ids ) {
        # update ignore so we don't raise duplicate key errors
        $dbh->do( 'UPDATE IGNORE wt_edges SET to_userid=? WHERE to_userid=?',
              undef, $to_u->id, $from_u->id );
        return (0,"Database Error: " . $dbh->errstr)
            if $dbh->err;

        # in the event that some rows in the update above caused a duplicate key error,
        # we can delete the rows that weren't updated, since they don't need to be
        # processed anyway
        $dbh->do( "DELETE FROM wt_edges WHERE to_userid=?", undef, $from_u->id );
        return (0,"Database Error: " . $dbh->errstr)
            if $dbh->err;

        # clear memcache keys
        foreach my $id ( @ids ) {
            LJ::memcache_kill( $id, 'wt_edges' );
            LJ::memcache_kill( $id, 'wt_list' );
            LJ::memcache_kill( $id, 'watched' );
        }

        LJ::memcache_kill( $from_u->id, 'wt_edges_rev' );
        LJ::memcache_kill( $from_u->id, 'watched_by' );

        LJ::memcache_kill( $to_u->id, 'wt_edges_rev' );
        LJ::memcache_kill( $to_u->id, 'watched_by' );
    }

    # log to statushistory
    my $remote = LJ::get_remote();
    my $msg = "Merged " . $from_u->user . " to " . $to_u->user . " using URL: $url.";
    LJ::statushistory_add($from_u, $remote, 'synd_merge', $msg . " Old URL was $from_oldurl.");
    LJ::statushistory_add($to_u, $remote, 'synd_merge', $msg . " Old URL was $to_oldurl.");

    return (1,$msg);
}

1;
