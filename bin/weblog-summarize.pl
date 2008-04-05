#!/usr/bin/perl
#

use strict;

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $lock = LJ::locker()->trylock("weblog-summarize");
exit 0 unless $lock;
print "Starting.\n";

my %name;
while (<DATA>) {
    next unless /(\S+)\s*\-\s*(.+)/;
    $name{$1} = $2;
}

my $db = LJ::get_dbh("logs");

my @tables;
my $sth = $db->prepare("SHOW TABLES LIKE 'access%'");
$sth->execute;
push @tables, $_ while $_ = $sth->fetchrow_array;

for (1..10*24) { pop @tables; }

my $ct;
my $sth;

$| = 1;

foreach my $t (@tables) {
    my $file = $t;
    $file =~ s/^access//;
    $file = "$LJ::HOME/var/stats-$file";
    next if -e "$file.gz";
    open (E, ">$file");

    print "$t\n";

    print "  hits...";
    $ct = $db->selectrow_array("SELECT COUNT(*) FROM $t");
    print E "count\thits\t$ct\n";
    print $ct, "\n";

    print "  bytes...";
    $ct = $db->selectrow_array("SELECT SUM(bytes) FROM $t");
    print E "count\tbytes\t$ct\n";
    print $ct, "\n";

    print "  ljusers...";
    $ct = $db->selectrow_array("SELECT COUNT(DISTINCT ljuser) FROM $t");
    print E "count\tuniq_ljuser\t$ct\n";
    print $ct, "\n";
    
    print "  codepath...\n";
    $sth = $db->prepare("SELECT codepath, COUNT(*) FROM $t GROUP BY 1 ORDER BY 2 DESC");
    $sth->execute;
    while (my ($p, $ct) = $sth->fetchrow_array) {
	print E "codepath\t$p\t$ct\n";
    }

    print "  status...\n";
    $sth = $db->prepare("SELECT status, COUNT(*) FROM $t GROUP BY 1 ORDER BY 2 DESC");
    $sth->execute;
    while (my ($s, $ct) = $sth->fetchrow_array) {
	print E "status\t$s\t$ct\n";
    }

    close E;
    system("/bin/gzip", $file) and die "Error gzipping $t\n";
    $db->do("DROP TABLE $t");
}

