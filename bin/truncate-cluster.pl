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

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

my $cid = shift;
die "Usage: truncate-cluster.pl <clusterid>\n" unless $cid =~ /^\d+$/;

my $dbh = LJ::get_db_writer();
my $ct  = $dbh->selectrow_array( "SELECT COUNT(*) FROM user WHERE clusterid=?", undef, $cid );
die $dbh->errstr if $dbh->err;

if ( $ct > 0 ) {
    die "Can't truncate a cluster with users.  Cluster \#$cid has $ct users.\n";
}

my $cm = LJ::get_cluster_master( { raw => 1 }, $cid );
die "Can't get handle to cluster \#$cid\n" unless $cm;

my $size;
foreach my $table ( sort ( @LJ::USER_TABLES, @LJ::USER_TABLES_LOCAL ) ) {
    my $ts = $cm->selectrow_hashref("SHOW TABLE STATUS like '$table'");
    die "Can't get table status for $table\n" unless $ts;
    print "Size of $table = $ts->{'Data_length'}\n";
    next unless $ts->{'Data_length'};
    $cm->do("TRUNCATE TABLE $table");
    die $cm->errstr if $cm->err;

    $size += $ts->{'Data_length'};

}
print "Total size truncated (excluding indexes): $size\n";
