#!/usr/bin/perl

use strict;
use Getopt::Long;

# load libraries now
use lib "$ENV{'LJHOME'}/cgi-bin";
use LJ::Blob;
use Image::Size ();
require "ljlib.pl";

my $opt_fast;
exit 1 unless
    GetOptions("fast" => \$opt_fast,
               );

my $clusterid = shift;
die "Usage: blobify_userpics.pl <clusterid>\n"
    unless $clusterid;

my $db = LJ::get_cluster_master($clusterid);
die "Invalid/down cluster: $clusterid\n" unless $db;

print "Getting count.\n";
my $total = $db->selectrow_array("SELECT COUNT(*) FROM userpicblob2");
my $done = 0;

my $loop = 1;
while ($loop) {
    $loop = 0;
    LJ::start_request();  # shrink caches
    print "Getting 200.\n";
    my $sth = $db->prepare("SELECT userid, picid, imagedata FROM userpicblob2 LIMIT 200");
    $sth->execute;
    while (my ($uid, $picid, $image) = $sth->fetchrow_array) {
        $loop = 1;
        my $u = LJ::load_userid($uid);
        die "Can't find userid: $uid" unless $u;

        # sometimes expunges don't expunge all the way.
        if ($u->{'statusvis'} eq "X") {
            $db->do("DELETE FROM userpicblob2 WHERE userid=$uid AND picid=$picid");
            next;
        }
        
        my ($sx, $sy, $fmt) = Image::Size::imgsize(\$image);
        die "Unknown format" unless $fmt eq "GIF" || $fmt eq "JPG" || $fmt eq "PNG";
        $fmt = lc($fmt);
        
        my $err;
        my $rv = LJ::Blob::put($u, "userpic", $fmt, $picid, $image, \$err);
        die "Error putting file: $u->{'user'}/$picid\n" unless $rv;

        unless ($opt_fast) {
            # extra paranoid!
            my $get = LJ::Blob::get($u, "userpic", $fmt, $picid);
            die "Re-fetch didn't match" unless $get eq $image;
        }

        $db->do("DELETE FROM userpicblob2 WHERE userid=$uid AND picid=$picid");

        $done++;
        printf " Moved $uid/$picid.$fmt ($done/$total = %.2f%%)\n", ($done / $total * 100);
    }
}

my $end_ct = $db->selectrow_array("SELECT COUNT(*) FROM userpicblob2");
if ($end_ct == 0) {
    $db->do("TRUNCATE TABLE userpicblob2");
}
print "Done.\n";

