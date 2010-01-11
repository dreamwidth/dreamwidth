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
