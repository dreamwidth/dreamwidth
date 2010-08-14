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

package LJ::Console::Command::SynMerge;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "syn_merge" }

sub desc { "Merge two syndicated accounts into one, setting up a redirect and using one account's URL." }

sub args_desc { [
                 'from_user' => "Syndicated account to merge into another.",
                 'to_user'   => "Syndicated account to merge 'from_user' into.",
                 'url'       => "Source feed URL to use for 'to_user'. Specify the direct URL to the feed.",
                 ] }

sub usage { '<from_user> "to" <to_user> "using" <url>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "syn_edit" );
}

sub execute {
    my ($self, $from_user, $to, $to_user, $using, $url, @args) = @_;

    return $self->error("This command takes five arguments. Consult the reference.")
        unless $from_user && $to_user && $url && scalar(@args) == 0;

    return $self->error("Second argument must be 'to'.")
        unless $to eq 'to';

    return $self->error("Fourth argument must be 'using'.")
        if $using ne 'using';

    my $from_u = LJ::load_user($from_user)
        or return $self->error("Invalid user: '$from_user'.");

    my $to_u = LJ::load_user($to_user)
        or return $self->error("Invalid user: '$to_user'.");

    return $self->error( "Trying to merge into yourself: '$to_user'." )
        if $from_u->equals( $to_u );

    # we don't want to unlimit this, so reject if we have too many users
    my @ids = $from_u->watched_by_userids( limit => $LJ::MAX_WT_EDGES_LOAD+1 );
    return $self->error( "Unable to merge feeds. Too many users are watching the feed '" . $from_u->user . "'. We only allow merges for feeds with at most $LJ::MAX_WT_EDGES_LOAD watchers." )
        if scalar @ids > $LJ::MAX_WT_EDGES_LOAD;

    foreach ($to_u, $from_u) {
        return $self->error("Invalid user: '" . $_->user . "' (statusvis is " . $_->statusvis . ", already merged?)")
            unless $_->is_visible;

        return $self->error($_->user . " is not a syndicated account.")
            unless $_->is_syndicated;
    }

    $url = LJ::CleanHTML::canonical_url($url)
        or return $self->error("Invalid URL.");

    my $dbh = LJ::get_db_writer();

    my $from_oldurl = $dbh->selectrow_array("SELECT synurl FROM syndicated WHERE userid=?", undef, $from_u->id);
    my $to_oldurl = $dbh->selectrow_array("SELECT synurl FROM syndicated WHERE userid=?", undef, $to_u->id);

    # 1) set up redirection for 'from_user' -> 'to_user'
    $from_u->update_self( { journaltype => 'R', statusvis => 'R' } );
    $from_u->set_prop("renamedto", $to_user)
        or return $self->error("Unable to set userprop.  Database unavailable?");

    # 2) delete the row in the syndicated table for the user
    #    that is now renamed
    $dbh->do("DELETE FROM syndicated WHERE userid=?",
             undef, $from_u->id);
    return $self->error("Database Error: " . $dbh->errstr)
        if $dbh->err;

    # 3) update the url of the destination syndicated account and
    #    tell it to check it now
    $dbh->do("UPDATE syndicated SET synurl=?, checknext=NOW() WHERE userid=?",
             undef, $url, $to_u->id);
    return $self->error("Database Error: " . $dbh->errstr)
        if $dbh->err;

    # 4) make users who watch 'from_user' now watch 'to_user'
    # we can't just use delete_ and add_ edges, because we would lose
    # custom group and colors data
    if ( @ids ) {
        # update ignore so we don't raise duplicate key errors
        $dbh->do( 'UPDATE IGNORE wt_edges SET to_userid=? WHERE to_userid=?',
              undef, $to_u->id, $from_u->id );
        return $self->error("Database Error: " . $dbh->errstr)
            if $dbh->err;

        # in the event that some rows in the update above caused a duplicate key error,
        # we can delete the rows that weren't updated, since they don't need to be
        # processed anyway
        $dbh->do( "DELETE FROM wt_edges WHERE to_userid=?", undef, $from_u->id );
        return $self->error("Database Error: " . $dbh->errstr)
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
    my $msg = "Merged $from_user to $to_user using URL: $url.";
    LJ::statushistory_add($from_u, $remote, 'synd_merge', $msg . " Old URL was $from_oldurl.");
    LJ::statushistory_add($to_u, $remote, 'synd_merge', $msg . " Old URL was $to_oldurl.");

    return $self->print($msg);
}

1;
