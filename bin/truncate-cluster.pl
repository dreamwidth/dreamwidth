#!/usr/bin/perl
#

use strict;
require "$ENV{LJHOME}/cgi-bin/ljlib.pl";

my $cid = shift;
die "Usage: truncate-cluster.pl <clusterid>\n" unless $cid =~ /^\d+$/;

my $dbh = LJ::get_db_writer();
my $ct = $dbh->selectrow_array("SELECT COUNT(*) FROM user WHERE clusterid=?", undef, $cid);
die $dbh->errstr if $dbh->err;

if ($ct > 0) {
    die "Can't truncate a cluster with users.  Cluster \#$cid has $ct users.\n";
}

my $cm = LJ::get_cluster_master({raw=>1}, $cid);
die "Can't get handle to cluster \#$cid\n" unless $cm;

my $size;
foreach my $table (sort (@LJ::USER_TABLES, @LJ::USER_TABLES_LOCAL)) {
    my $ts = $cm->selectrow_hashref("SHOW TABLE STATUS like '$table'");
    die "Can't get table status for $table\n" unless $ts;
    print "Size of $table = $ts->{'Data_length'}\n";
    next unless $ts->{'Data_length'};
    $cm->do("TRUNCATE TABLE $table");
    die $cm->errstr if $cm->err;

    $size += $ts->{'Data_length'};
    
}
print "Total size truncated (excluding indexes): $size\n";
