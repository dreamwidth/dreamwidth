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

package LJ::SiteMessages;
use strict;
use Carp qw(croak);

sub memcache_key {
    my $class = shift;

    return "sitemessages";
}

sub cache_get {
    my $class = shift;

    # first, is it in our per-request cache?
    my $questions = $LJ::SiteMessages::REQ_CACHE_MESSAGES;
    return $questions if $questions;

    my $memkey = $class->memcache_key;
    my $memcache_data = LJ::MemCache::get($memkey);
    if ($memcache_data) {
        # fill the request cache since it was empty
        $class->request_cache_set($memcache_data);
    }
    return $memcache_data;
}

sub request_cache_set {
    my $class = shift;
    my $val = shift;

    $LJ::SiteMessages::REQ_CACHE_MESSAGES = $val;
}

sub cache_set {
    my $class = shift;
    my $val = shift;

    # first set in request cache
    $class->request_cache_set($val);

    # now set in memcache
    my $memkey = $class->memcache_key;
    my $expire = 60*5; # 5 minutes
    return LJ::MemCache::set($memkey, $val, $expire);
}

sub cache_clear {
    my $class = shift;

    # clear request cache
    $LJ::SiteMessages::REQ_CACHE_MESSAGES = undef;

    # clear memcache
    my $memkey = $class->memcache_key;
    return LJ::MemCache::delete($memkey);
}

sub load_messages {
    my $class = shift;
    my %opts = @_;

    my $messages = $class->cache_get;
    return @$messages if $messages;

    my $dbh = LJ::get_db_writer()
        or die "no global database writer for SiteMessages";

    my $sth = $dbh->prepare(
        "SELECT * FROM site_messages WHERE time_start <= UNIX_TIMESTAMP() AND time_end >= UNIX_TIMESTAMP() AND active='Y'"
    );
    $sth->execute;

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }
    $class->cache_set(\@rows);

    return @rows;
}

sub get_messages {
    my $class = shift;
    my %opts = @_;

    my @messages = $class->load_messages;

    # sort messages in descending order by start time (newest first)
    @messages = 
        sort { $b->{time_start} <=> $a->{time_start} } 
        grep { ref $_ } @messages;

    return @messages;
}

sub store_message {
    my $class = shift;
    my %vals = @_;

    my $dbh = LJ::get_db_writer()
        or die "Unable to store message: no global dbh";

    my $mid;

    # update existing message
    if ($vals{mid}) {
        $dbh->do("UPDATE site_messages SET time_start=?, time_end=?, active=?, text=? WHERE mid=?",
                 undef, (map { $vals{$_} } qw(time_start time_end active text mid)))
            or die "Error updating site_messages: " . $dbh->errstr;
        $mid = $vals{mid};
    }
    # insert new message
    else {
        $dbh->do("INSERT INTO site_messages VALUES (?,?,?,?,?)",
                 undef, "null", (map { $vals{$_} } qw(time_start time_end active text)))
            or die "Error adding site_messages: " . $dbh->errstr;
        $mid = $dbh->{mysql_insertid};
    }

    # insert/update message in translation system
    my $ml_key = LJ::Widget::SiteMessages->ml_key("$mid.text");
    LJ::Widget->ml_set_text($ml_key => $vals{text});

    # clear cache
    $class->cache_clear;
    return 1;
}

# returns all messages that started during the given month
sub get_all_messages_for_month {
    my $class = shift;
    my ($year, $month) = @_;

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

    my $time_start = DateTime->new( year => $year, month => $month, time_zone => 'America/Los_Angeles' );
    my $time_end = $time_start->clone;
    $time_end = $time_end->add( months => 1 );
    $time_end = $time_end->subtract( seconds => 1 ); # we want time_end to be the end of the last day of the month

    my $sth = $dbh->prepare("SELECT * FROM site_messages WHERE time_start >= ? AND time_start <= ?");
    $sth->execute($time_start->epoch, $time_end->epoch)
        or die "Error getting this month's messages: " . $dbh->errstr;

    my @rows = ();
    while (my $row = $sth->fetchrow_hashref) {
        push @rows, $row;
    }

    # sort messages in descending order by start time (newest first)
    @rows =
        sort { $b->{time_start} <=> $a->{time_start} }
        grep { ref $_ } @rows;

    return @rows;
}

# given an id for a message, returns the info for it
sub get_single_message {
    my $class = shift;
    my $mid = shift;

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

    my $sth = $dbh->prepare("SELECT * FROM site_messages WHERE mid = ?");
    $sth->execute($mid)
        or die "Error getting single message: " . $dbh->errstr;

    return $sth->fetchrow_hashref;
}

# change the active status of the given message
sub change_active_status {
    my $class = shift;
    my $mid = shift;

    my %opts = @_;
    my $to = delete $opts{to};
    croak "invalid 'to' field" unless $to =~ /^(active|inactive)$/; 

    my $question = $class->get_single_message($mid)
        or die "Invalid message: $mid";

    my $dbh = LJ::get_db_writer()
        or die "Error: no global dbh";

    my $active_val = $to eq 'active' ? 'Y' : 'N';
    my $rv = $dbh->do("UPDATE site_messages SET active = ? WHERE mid = ?", undef, $active_val, $mid)
        or die "Error updating active status of message: " . $dbh->errstr;

    $class->cache_clear;

    return $rv;
}

1;
