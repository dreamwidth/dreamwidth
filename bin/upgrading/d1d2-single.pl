#!/usr/bin/perl
#

use strict;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
my $dbh = LJ::get_dbh("master");

my $user = shift @ARGV;
my $where = "dversion=1 LIMIT 1";
if ($user) {
    $where = "user=" . $dbh->quote($user);
}

my $u = $dbh->selectrow_hashref("SELECT * FROM user WHERE $where");
unless ($u) {
    die "No users with dversion==1 to convert.  Done.\n" unless $user;
    die "User not found.\n";
}

die "User not dversion 1\n" unless $u->{'dversion'} == 1;

my $dbch = LJ::get_cluster_master($u);
die "Can't connect to cluster master.\n" unless $dbch;

print "$u->{'user'}:\n";
my @pics = @{$dbh->selectcol_arrayref("SELECT picid FROM userpic WHERE ".
                                      "userid=$u->{'userid'}")};
foreach my $picid (@pics) {
    print "  $picid...\n";
    my $imagedata = $dbh->selectrow_array("SELECT imagedata FROM userpicblob ".
                                          "WHERE picid=$picid");
    $imagedata = $dbh->quote($imagedata);
    $dbch->do("REPLACE INTO userpicblob2 (userid, picid, imagedata) VALUES ".
              "($u->{'userid'}, $picid, $imagedata)");
}

$dbh->do("UPDATE user SET dversion=2 WHERE userid=$u->{'userid'}");
print "Done.\n";


