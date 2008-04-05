#!/usr/bin/perl
#
# This script converts from dversion 2 (clustered + userpicblobs clustered)
# to dversion 3, which adds weekuserusage population.
#

use strict;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

die "This script is no longer useful.\n";

my $dbh = LJ::get_db_writer();

my $todo = $dbh->selectrow_array("SELECT COUNT(*) FROM user WHERE dversion=2");
my $done = 0;
unless ($todo) {
    print "Nothing to convert.\n";
    exit 0;
}

sub get_some {
    my @list;
    my $sth = $dbh->prepare("SELECT * FROM user WHERE dversion=2 LIMIT 200");
    $sth->execute;
    push @list, $_ while $_ = $sth->fetchrow_hashref;
    @list;
}

print "Converting $todo users from data version 2 to 3...\n";
my $start = time();
while (my @list = get_some()) {
    LJ::start_request();
    foreach my $u (@list) {
        my $dbcm = LJ::get_cluster_master($u);
        next unless $dbcm;

        my %week;
        my $sth = $dbcm->prepare("SELECT rlogtime FROM log2 ".
                                 "WHERE journalid=? AND rlogtime < 2147483647");
        $sth->execute($u->{'userid'});
        while (my $t = $sth->fetchrow_array) {
            my ($week, $uafter, $ubefore) = LJ::weekuu_parts($t);
            if (! $week{$week}) {
                $week{$week} = [ $uafter, $ubefore ];
            } elsif ($ubefore < $week{$week}->[1]) {
                $week{$week}->[1] = $ubefore;
            }
        }

        if (%week) {
            my $sql = "REPLACE INTO weekuserusage (wknum,userid,uafter,ubefore) VALUES " .
                join(",", map { "($_,$u->{'userid'},$week{$_}->[0],$week{$_}->[1])" } keys %week);
            my $rv = $dbh->do($sql);
            die $dbh->errstr if $dbh->err;
            next unless $rv;  # error? try later.
        }
        
        $dbh->do("UPDATE user SET dversion=3 WHERE userid=?", undef, $u->{'userid'});
        $done++;
    }
      
    my $perc = $done/$todo;
    my $elapsed = time() - $start;
    my $total_time = $elapsed / $perc;
    my $min_remain = int(($total_time - $elapsed) / 60);
    printf "%d/%d complete (%.02f%%) minutes_remain=%d\n", $done, $todo, ($perc*100), $min_remain;
}
