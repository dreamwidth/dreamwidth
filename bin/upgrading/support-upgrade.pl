#!/usr/bin/perl
#

require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";

my $dbh = LJ::get_dbh("master");
my $sth;

$sth = $dbh->prepare("SELECT spid FROM support WHERE timelasthelp IS NULL");
$sth->execute;
while (my ($spid) = $sth->fetchrow_array)
{
    print "Fixing $spid...\n";
    my $st2 = $dbh->prepare("SELECT MAX(timelogged) FROM supportlog WHERE spid=$spid AND type='answer'");
    $st2->execute;
    my ($max) = $st2->fetchrow_array;
    $max = $max + 0;   # turn undef -> 0
    print "  time = $max\n";
    $dbh->do("UPDATE support SET timelasthelp=$max WHERE spid=$spid");

}
