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

package LJ::UserSearch::MetaUpdater;

use strict;
use warnings;
use List::Util ();
use Fcntl qw(:seek :DEFAULT);
use LJ::User;
use LJ::Directory::PackedUserRecord;
use LJ::Directory::MajorRegion;

sub update_user {
    my $u   = LJ::want_user(shift) or die "No userid specified";
    my $dbh = LJ::get_db_writer()  or die "No db";
    my $dbs =
        defined $LJ::USERSEARCH_DB_WRITER
        ? LJ::get_dbh($LJ::USERSEARCH_DB_WRITER)
        : LJ::get_db_writer();
    die "No db" unless $dbs;

    if ( $u->is_expunged ) {
        $dbs->do(
            "REPLACE INTO usersearch_packdata (userid, packed, good_until, mtime) "
                . "VALUES (?, ?, ?, UNIX_TIMESTAMP())",
            undef, $u->id, "\0" x 8, undef
        );
        return 1;
    }

    my $lastmod = $dbh->selectrow_array(
        "SELECT UNIX_TIMESTAMP(timeupdate) " . "FROM userusage WHERE userid=?",
        undef, $u->id );

    my ( $age, $good_until ) = $u->usersearch_age_with_expire;

    my $regid = LJ::Directory::MajorRegion->most_specific_matching_region_id( $u->prop("country"),
        $u->prop("state"), $u->prop("city") );

    my $newpack = LJ::Directory::PackedUserRecord->new(
        updatetime  => $lastmod,
        age         => $age,
        journaltype => $u->journaltype,
        regionid    => $regid,
    )->packed;

    my $rv = $dbs->do(
        "REPLACE INTO usersearch_packdata (userid, packed, good_until, mtime) "
            . "VALUES (?, ?, ?, UNIX_TIMESTAMP())",
        undef, $u->id, $newpack, $good_until
    );

    die "DB Error: " . $dbh->errstr if $dbh->errstr;
    return 1;
}

# pass this a time and it will update the in-memory usersearch map
# with the users updated since the time
sub update_users {
    my $starttime = shift;

    my $dbr =
        defined $LJ::USERSEARCH_DB_READER
        ? LJ::get_dbh($LJ::USERSEARCH_DB_READER)
        : LJ::get_db_reader();
    die "No db" unless $dbr;

    unless ( LJ::ModuleCheck->have("LJ::UserSearch") ) {
        die "Missing module 'LJ::UserSearch'\n";
    }

    my $sth = $dbr->prepare( "SELECT userid, packed, mtime FROM usersearch_packdata "
            . "WHERE mtime >= ? ORDER BY mtime LIMIT 1000" );
    $sth->execute($starttime);
    die $sth->errstr if $sth->err;

    my $endtime = $starttime;

    while ( my $row = $sth->fetchrow_arrayref ) {
        my ( $userid, $packed, $mtime ) = @$row;
        $endtime = $mtime;
        LJ::UserSearch::update_user( $userid, $packed );
    }

    return $endtime;
}

sub missing_rows {
    my $dbh = LJ::get_db_writer() or die "No db";
    my $dbs =
        defined $LJ::USERSEARCH_DB_WRITER
        ? LJ::get_dbh($LJ::USERSEARCH_DB_WRITER)
        : LJ::get_db_writer();
    die "No db" unless $dbs;
    my $highest_uid = $dbh->selectrow_array("SELECT MAX(userid) FROM user") || 0;
    my $highest_search_uid =
        $dbs->selectrow_array("SELECT MAX(userid) FROM usersearch_packdata") || 0;
    return $highest_uid != $highest_search_uid;
}

sub add_some_missing_rows {
    my $dbh = LJ::get_db_writer() or die "No db";
    my $dbs =
        defined $LJ::USERSEARCH_DB_WRITER
        ? LJ::get_dbh($LJ::USERSEARCH_DB_WRITER)
        : LJ::get_db_writer();
    die "No db" unless $dbs;
    my $highest_search_uid =
        $dbs->selectrow_array("SELECT MAX(userid) FROM usersearch_packdata") || 0;
    my $sth = $dbh->prepare("SELECT userid FROM user WHERE userid > ? ORDER BY userid LIMIT 500");
    $sth->execute($highest_search_uid);
    my @ids;
    while ( my ($uid) = $sth->fetchrow_array ) {
        push @ids, $uid;
    }
    my $vals = join( ",", map { "($_,0)" } @ids );

    if ($vals) {
        $dbs->do( "INSERT IGNORE INTO usersearch_packdata (userid, good_until) " . "VALUES $vals" )
            or die;
        return 1;
    }
    return 0;
}

sub update_some_rows {
    my $dbh =
        defined $LJ::USERSEARCH_DB_WRITER
        ? LJ::get_dbh($LJ::USERSEARCH_DB_WRITER)
        : LJ::get_db_writer();
    die "No db" unless $dbh;
    my $ids = $dbh->selectcol_arrayref(
        "SELECT userid FROM usersearch_packdata WHERE good_until <= UNIX_TIMESTAMP() LIMIT 1000");
    my $updated = 0;
    foreach my $uid ( List::Util::shuffle(@$ids) ) {
        my $lock = LJ::locker()->trylock("dirpackupdate:$uid")
            or next;

        if (
            $dbh->selectrow_array(
"SELECT (good_until IS NULL or good_until > UNIX_TIMESTAMP()) FROM usersearch_packdata WHERE userid=?",
                undef,
                $uid
            )
            )
        {
            # already done!  (by other process)
            next;
        }

        my $u = LJ::load_userid($uid);
        $updated++
            if LJ::UserSearch::MetaUpdater::update_user($u);

        # only do 1/10th of what we selected out, as the rate of already-done-by-other-thread items
        # goes up and up as we get to the end of the list.
        last if $updated >= 100;
    }
    return $updated;
}

sub update_file {
    my $filename = shift;

    my $dbh =
        defined $LJ::USERSEARCH_DB_READER
        ? LJ::get_dbh($LJ::USERSEARCH_DB_READER)
        : LJ::get_db_reader();
    die "No db" unless $dbh;

    sysopen( my $fh, $filename, O_RDWR | O_CREAT )
        or die "Couldn't open file '$filename' for read/write: $!";
    unless ( -s $filename >= 8 ) {
        my $zeros = "\0" x 8;
        syswrite( $fh, $zeros );
    }

    while ( update_file_partial( $dbh, $fh ) ) {

        # do more.
    }
    return 1;
}

# Iterate over a limited number of usersearch data updates and write them to the packdata filehandle.
#
# Args:
# $dbh - Database handle to read for usersearch data from.
# $fh  - Filehandle to read and write to
# $limit_num - Maximum number of updates to process this run
#
# Returns number of actual records updated.

sub update_file_partial {
    my ( $dbh, $fh, $limit_num ) = @_;

    $limit_num ||= 10000;
    $limit_num += 0;
    die "Can't attempt an update of $limit_num records, which is not a positive number."
        unless $limit_num > 0;

    sysseek( $fh, 0, SEEK_SET ) or die "Couldn't seek: $!";

    sysread( $fh, my $header, 8 ) == 8 or die "Couldn't read 8 byte header: $!";
    my ( $file_lastmod, $nr_disk_thatmod ) = unpack( "NN", $header );

    # the on-disk file and database only keeps second granularity.  if
    # the number of records changed in that particular second changed,
    # step back in time one second and we'll redo a few records, but
    # be sure not to miss any.
    my $nr_db_thatmod =
        $dbh->selectrow_array( "SELECT COUNT(*) FROM usersearch_packdata WHERE mtime=?",
        undef, $file_lastmod );

    if ( $nr_db_thatmod != $nr_disk_thatmod ) {
        $file_lastmod--;
    }

    my $sth =
        $dbh->prepare( "SELECT userid, packed, mtime FROM usersearch_packdata WHERE mtime > ? AND "
            . "(good_until IS NULL OR good_until > unix_timestamp()) ORDER BY mtime LIMIT $limit_num"
        );
    $sth->execute($file_lastmod);

    die "DB Error: " . $sth->errstr if $sth->errstr;

    my $nr_with_highest_mod = 0;
    my $last_mtime          = 0;
    my $rows                = 0;

    while ( my ( $userid, $packed, $mtime ) = $sth->fetchrow_array ) {
        unless ( length($packed) == 8 ) {
            die "Pack length was incorrect";
        }
        my $offset = $userid * 8;
        sysseek( $fh, $offset, SEEK_SET ) or die "Couldn't seek: $!";
        syswrite( $fh, $packed ) == 8 or die "Syswrite failed to complete: $!";
        $rows++;

        if ( $last_mtime == $mtime ) {
            $nr_with_highest_mod++;
        }
        else {
            $nr_with_highest_mod = 1;
            $last_mtime          = $mtime;
        }
    }

    # Don't update the header on the file if we didn't actually do any updates.
    return 0 unless $rows;

    sysseek( $fh, 0, SEEK_SET ) or die "Couldn't seek: $!";
    my $newheader = pack( "NN", $last_mtime, $nr_with_highest_mod );
    syswrite( $fh, $newheader ) == 8 or die "Couldn't write header: $!";

    return $rows;
}

1;
