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

use strict;

our %maint;

$maint{'clean_caches'} = sub
{
    my $dbh = LJ::get_db_writer();
    my $sth;

    my $verbose = $LJ::LJMAINT_VERBOSE;

    print "-I- Cleaning authactions.\n";
    $dbh->do("DELETE FROM authactions WHERE datecreate < DATE_SUB(NOW(), INTERVAL 30 DAY)");

    print "-I- Cleaning faquses.\n";
    $dbh->do("DELETE FROM faquses WHERE dateview < DATE_SUB(NOW(), INTERVAL 7 DAY)");

    print "-I- Cleaning duplock.\n";
    $dbh->do("DELETE FROM duplock WHERE instime < DATE_SUB(NOW(), INTERVAL 1 HOUR)");

    print "-I- Cleaning underage uniqs.\n";
    $dbh->do("DELETE FROM underage WHERE timeof < (UNIX_TIMESTAMP() - 86400*90) LIMIT 2000");

    print "-I- Cleaning blobcache.\n";
    $dbh->do("DELETE FROM blobcache WHERE dateupdate < NOW() - INTERVAL 30 DAY");

    print "-I- Cleaning old anonymous comment IP logs.\n";
    my $count;
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        next unless $dbcm;
        # 432,000 seconds is 5 days
        $count += $dbcm->do('DELETE FROM tempanonips WHERE reporttime < (UNIX_TIMESTAMP() - 432000)');
    }
    print "    deleted $count\n";

    print "-I- Cleaning old random users.\n";
    my $count;
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        next unless $dbcm;

        my $secs = $LJ::RANDOM_USER_PERIOD * 24 * 60 * 60;
        while (my $deleted = $dbcm->do("DELETE FROM random_user_set WHERE posttime < (UNIX_TIMESTAMP() - $secs) LIMIT 1000")) {
            $count += $deleted;

            last if $deleted != 1000;
            sleep 10;
        }
    }
    print "    deleted $count\n";

    print "-I- Cleaning old pending comments.\n";
    $count = 0;
    foreach my $c (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($c);
        next unless $dbcm;
        # 3600 seconds is one hour
        my $time = time() - 3600;
        $count += $dbcm->do('DELETE FROM pendcomments WHERE datesubmit < ? LIMIT 2000', undef, $time);
    }
    print "    deleted $count\n";

    # move rows from talkleft_xfp to talkleft
    print "-I- Moving talkleft_xfp.\n";

    my $xfp_count = $dbh->selectrow_array("SELECT COUNT(*) FROM talkleft_xfp");
    print "    rows found: $xfp_count\n";

    if ($xfp_count) {

        my @xfp_cols = qw(userid posttime journalid nodetype nodeid jtalkid publicitem);
        my $xfp_cols = join(",", @xfp_cols);
        my $xfp_cols_join = join(",", map { "t.$_" } @xfp_cols);

        my %insert_vals;
        my %delete_vals;

        # select out 1000 rows from random clusters
        $sth = $dbh->prepare("SELECT u.clusterid,u.user,$xfp_cols_join " .
                             "FROM talkleft_xfp t, user u " .
                             "WHERE t.userid=u.userid LIMIT 1000");
        $sth->execute();
        my $row_ct = 0;
        while (my $row = $sth->fetchrow_hashref) {

            my %qrow = map { $_, $dbh->quote($row->{$_}) } @xfp_cols;

            push @{$insert_vals{$row->{'clusterid'}}},
                   ("(" . join(",", map { $qrow{$_} } @xfp_cols) . ")");
            push @{$delete_vals{$row->{'clusterid'}}},
                   ("(userid=$qrow{'userid'} AND " .
                    "journalid=$qrow{'journalid'} AND " .
                    "nodetype=$qrow{'nodetype'} AND " .
                    "nodeid=$qrow{'nodeid'} AND " .
                    "posttime=$qrow{'posttime'} AND " .
                    "jtalkid=$qrow{'jtalkid'})");

            $row_ct++;
        }

        foreach my $clusterid (sort keys %insert_vals) {
            my $dbcm = LJ::get_cluster_master($clusterid);
            unless ($dbcm) {
                print "    cluster down: $clusterid\n";
                next;
            }

            print "    cluster $clusterid: " . scalar(@{$insert_vals{$clusterid}}) .
                  " rows\n" if $verbose;
            $dbcm->do("INSERT INTO talkleft ($xfp_cols) VALUES " .
                      join(",", @{$insert_vals{$clusterid}})) . "\n";
            if ($dbcm->err) {
                print "    db error (insert): " . $dbcm->errstr . "\n";
                next;
            }

            # no error, delete from _xfp
            $dbh->do("DELETE FROM talkleft_xfp WHERE " .
                     join(" OR ", @{$delete_vals{$clusterid}})) . "\n";
            if ($dbh->err) {
                print "    db error (delete): " . $dbh->errstr . "\n";
                next;
            }
        }

        print "    rows remaining: " . ($xfp_count - $row_ct) . "\n";
    }

    # move clustered active_user stats from each cluster to the global active_user_summary table
    print "-I- Migrating active_user records.\n";
    $count = 0;
    foreach my $cid (@LJ::CLUSTERS) {
        next unless $cid;

        my $dbcm = LJ::get_cluster_master($cid);
        unless ($dbcm) {
            print "    cluster down: $cid\n";
            next;
        }

        unless ($dbcm->do("LOCK TABLES active_user WRITE")) {
            print "    db error (lock): " . $dbcm->errstr . "\n";
            next;
        }

        # We always want to keep at least an hour worth of data in the
        # clustered table for duplicate checking.  We won't select out
        # any rows for this hour or the full hour before in order to avoid
        # extra rows counted in hour-boundary edge cases
        my $now = time();

        # one hour from the start of this hour (
        my $before_time = $now - 3600 - ($now % 3600);
        my $time_str = LJ::mysql_time($before_time, 'gmt');

        # now extract parts from the modified time
        my ($yr, $mo, $day, $hr) =
            $time_str =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d)/;

        # Building up all this sql is pretty messy but otherwise it
        # becomes unwieldy with tons of code duplication and more places
        # for this fairly-complicated where condition to break.  So we'll
        # build a nice where clause which uses bind vars and then create
        # an array to go inline in the spot where those bind vars should
        # be within the larger query
        my $where = "WHERE year=? AND month=? AND day=? AND hour<? OR " .
                    "year=? AND month=? AND day<? OR " .
                    "year=? AND month<? OR " .
                    "year<?";

        my @where_vals = ($yr, $mo, $day, $hr,
                          $yr, $mo, $day,
                          $yr, $mo,
                          $yr                );

        # This is kind of a hack. We have a situation right now where we allow
        # imports to override the userpic quota for a user, because we want to
        # import everything we can. But we need a way to, later, go through
        # and deactivate those userpics. We are doing that here so that the
        # problem only lasts for a day or so.
        my $sth = $dbcm->prepare(
            "SELECT DISTINCT userid FROM active_user $where");
        $sth->execute(@where_vals);
        unless ($dbcm->err) {
            while (my ($uid) = $sth->fetchrow_array) {
                my $u = LJ::load_userid($uid) or next; # Best effort.
                $u->activate_userpics;
            }
        }

        # don't need to check for distinct userid in the count here
        # because y,m,d,h,uid is the primary key so we know it's
        # unique for this hour anyway
        my $sth = $dbcm->prepare
            ("SELECT type, year, month, day, hour, COUNT(userid) " .
             "FROM active_user $where GROUP BY 1,2,3,4,5");
        $sth->execute(@where_vals);

        if ($dbcm->err) {
            print "    db error (select): " . $dbcm->errstr . "\n";
            next;
        }

        my %counts = ();
        my $total_ct = 0;
        while (my ($type, $yr, $mo, $day, $hr, $ct) = $sth->fetchrow_array) {
            $counts{"$yr-$mo-$day-$hr-$type"} += $ct;
            $total_ct += $ct;
        }

        print "    cluster $cid: $total_ct rows\n" if $verbose;

        # Note: We can experience failures on both sides of this
        #       transaction.  Either our delete can succeed then
        #       insert fail or vice versa.  Luckily this data is
        #       for statistical purposes so we can just live with
        #       the possibility of a small skew.

        unless ($dbcm->do("DELETE FROM active_user $where", undef, @where_vals)) {
            print "    db error (delete): " . $dbcm->errstr . "\n";
            next;
        }

        # at this point if there is an error we will ignore it and try
        # to insert the count data above anyway
        my $rv = $dbcm->do("UNLOCK TABLES")
            or print "    db error (unlock): " . $dbcm->errstr . "\n";

        # nothing to insert, why bother?
        next unless %counts;

        # insert summary into active_user_summary table
        my @bind = ();
        my @vals = ();
        while (my ($hkey, $ct) = each %counts) {

            # yyyy, mm, dd, hh, cid, type, ct
            push @bind, "(?, ?, ?, ?, ?, ?, ?)";

            my ($yr, $mo, $day, $hr, $type) = split(/-/, $hkey);
            push @vals, ($yr, $mo, $day, $hr, $cid, $type, $ct);
        }
        my $bind = join(",", @bind);

        $dbh->do("INSERT IGNORE INTO active_user_summary (year, month, day, hour, clusterid, type, count) " .
                 "VALUES $bind", undef, @vals);

        if ($dbh->err) {
            print "    db error (insert): " . $dbh->errstr . "\n";

            # something's badly b0rked, don't try any other clusters for now
            last;
        }

        # next cluster
    }
};

1;
