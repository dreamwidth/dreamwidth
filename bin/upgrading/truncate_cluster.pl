#!/usr/bin/perl
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

my $clusterid = shift;
die "Usage: truncate_cluster.pl <clusterid>\n"
    unless $clusterid;

# load libraries now
BEGIN {
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
}

# force this option on, since that's the point of the tool
$LJ::COMPRESS_TEXT = 1;

my $master = LJ::get_db_writer();
my $ct = $master->selectrow_array("SELECT COUNT(*) FROM user WHERE clusterid=?",
			       undef, $clusterid);
if ($ct) {
    die "There are still $ct users on cluster $clusterid\n";
}

my $db = LJ::get_cluster_master($clusterid);
die "Invalid/down cluster: $clusterid\n" unless $db;

my $sth = $db->prepare("SHOW TABLES");
$sth->execute;

while (my $table = $sth->fetchrow_array) {
    next if $table eq "useridmap";
    print "  truncating $table\n";
    $db->do("TRUNCATE TABLE $table");
}
