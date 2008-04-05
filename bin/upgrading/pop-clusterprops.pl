#!/usr/bin/perl
#
# This script converts from dversion 3 to dversion 4,
# which makes most userprops clustered
#

use strict;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $fromver = shift;
die "Usage: pop-clusterprops.pl <fromdversion>\n\t(where fromdversion is one of: 3)\n"
    unless $fromver == 3;

my $dbh = LJ::get_db_writer();

my $todo = $dbh->selectrow_array("SELECT COUNT(*) FROM user WHERE dversion=$fromver");
my $done = 0;
unless ($todo) {
    print "Nothing to convert.\n";
    exit 0;
}

sub get_some {
    my @list;
    my $sth = $dbh->prepare("SELECT * FROM user WHERE dversion=$fromver LIMIT 200");
    $sth->execute;
    push @list, $_ while $_ = $sth->fetchrow_hashref;
    @list;
}

my $tover = $fromver + 1;
print "Converting $todo users from data version $fromver to $tover...\n";

my @props;
my $sth = $dbh->prepare("SELECT upropid FROM userproplist WHERE cldversion=?");
$sth->execute($tover);
push @props, $_ while $_ = $sth->fetchrow_array;
my $in = join(',', @props);
die "No values?" unless $in;

my $start = time();
while (my @list = get_some()) {
    LJ::start_request();
      
    my %cluster;  # clusterid -> [ $u* ]
    foreach my $u (@list) {
        push @{$cluster{$u->{'clusterid'}}}, $u;
    }

    foreach my $cid (keys %cluster) {
        my $dbcm = LJ::get_cluster_master($cid);
        next unless $dbcm;
        
        my $uid_in = join(',', map { $_->{'userid'} } @{$cluster{$cid}});

        my @vals;
        foreach my $table (qw(userprop userproplite)) {
            $sth = $dbh->prepare("SELECT userid, upropid, value FROM $table ".
                                 "WHERE userid IN ($uid_in) AND upropid IN ($in)");
            $sth->execute();
            while (my ($uid, $pid, $v) = $sth->fetchrow_array) {
                push @vals, "($uid,$pid," . $dbh->quote($v) . ")";
            }
        }
        if (@vals) {
            my $sql = "REPLACE INTO userproplite2 VALUES " . join(',', @vals);
            $dbcm->do($sql);
            if ($dbcm->err) {
                die "Error: " . $dbcm->errstr . "\n\n(Do you need to --runsql on your clusters first?)\n";
            }
            $dbh->do("DELETE FROM userprop WHERE userid IN ($uid_in) AND upropid IN ($in)");
            $dbh->do("DELETE FROM userproplite WHERE userid IN ($uid_in) AND upropid IN ($in)");
        }
        $dbh->do("UPDATE user SET dversion=$tover WHERE userid IN ($uid_in) AND dversion=$fromver");
        $done += scalar @{$cluster{$cid}};
    }

    my $perc = $done/$todo;
    my $elapsed = time() - $start;
    my $total_time = $elapsed / $perc;
    my $min_remain = int(($total_time - $elapsed) / 60);
    printf "%d/%d complete (%.02f%%) minutes_remain=%d\n", $done, $todo, ($perc*100), $min_remain;
}
