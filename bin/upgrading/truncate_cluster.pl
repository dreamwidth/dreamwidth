#!/usr/bin/perl

use strict;

my $clusterid = shift;
die "Usage: truncate_cluster.pl <clusterid>\n"
    unless $clusterid;

# load libraries now
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

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
