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

use strict;

BEGIN {
    die "\$LJHOME not set.\n" unless ( -d $ENV{'LJHOME'} );
    require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
}

my $db = LJ::get_dbh("logs");
unless ($db) {
    die "No 'logs' db handle found.\n";
}
$db->{'InactiveDestroy'} = 1;
my $sth;

my %table;
$sth = $db->prepare("SHOW TABLES LIKE 'access%'");
$sth->execute;
while (my $t = $sth->fetchrow_array) {
    $table{$t} = 1;
}

my @need_summary = sort grep { /^access\d{8,8}$/ } keys %table;
pop @need_summary; # don't summarize the current day yet.

my $nsum_total = @need_summary;
my $nsum_ct = 0;

use constant F_SERVER => 0;
use constant F_LANG => 1;
use constant F_METHOD => 2;
use constant F_VHOST => 3;
use constant F_URI => 4;
use constant F_STATUS => 5;
use constant F_CTYPE => 6;
use constant F_BYTES => 7;
use constant F_BROWSER => 8;
use constant F_REF => 9;

foreach my $table (@need_summary)
{
    $nsum_ct++;
    print "Summarizing $table ($nsum_ct/$nsum_total)\n";

    my $row_total = $db->selectrow_array("SELECT COUNT(*) FROM $table");
    print "  rows = $row_total\n";

    my $sth = $db->prepare("SELECT server, langpref, method, vhost, uri, ".
			   "       status, ctype, bytes, browser, ref ".
			   "FROM $table");
    $sth->{'mysql_use_result'} = 1;
    $sth->execute;
    my ($r, $row_ct);
    my %st;
    while ($r = $sth->fetchrow_arrayref) {
	$row_ct++;
	if ($row_ct % 10000 == 0) { 
	    printf "  $row_ct/$row_total (%%%.02f)\n", 100*$row_ct/$row_total;
	}
	
	next if ($r->[F_URI] =~ m!^/userpic!);


	$st{'count'}->{'total'}++;
	$st{'count'}->{'bytes'} += $r->[F_BYTES];
	$st{'http_meth'}->{$r->[F_METHOD]}++;
	$st{'http_status'}->{$r->[F_STATUS]}++;
	$st{'browser'}->{$r->[F_BROWSER]}++;
	$st{'host'}->{$r->[F_VHOST]}++;

	if ($r->[F_URI] =~ s!^/(users/|~)\w+/?!/users/*/!) {
	    $r->[F_URI] =~ s!day/\d\d\d\d/\d\d/\d\d!day!;
	    $r->[F_URI] =~ s!calendar/\d\d\d\d!calendar!;
	}

	if ($r->[F_VHOST] =~ /^(www\.)livejournal\.com$/) {
	    $st{'uri'}->{$r->[F_URI]}++;
	} else {
	    $r->[F_URI] =~ s!day/\d\d\d\d/\d\d/\d\d!day!;
	    $r->[F_URI] =~ s!calendar/\d\d\d\d!calendar!;
	    $st{'uri'}->{"user:" . $r->[F_URI]}++;
	}

	my $ref = $r->[F_REF];
	if ($ref =~ m!^http://([^/]+)!) {
	    $ref = $1;
	    $st{'referer'}->{$ref}++ unless ($ref =~ /livejournal\.com$/);
	}
    }

    my $tabledate = $table;
    $tabledate =~ s/^access//;

    print "  Writing stats file.\n";
    open (S, "| gzip -c > $ENV{'LJHOME'}/var/stats-$tabledate.gz") or die "Can't open stats file";
    foreach my $cat (sort keys %st) {
	print "Writing cat: $cat\n";
	foreach my $k (sort { $st{$cat}->{$b} <=> $st{$cat}->{$a} } keys %{$st{$cat}}) {
	    print S "$cat\t$k\t$st{$cat}->{$k}\n"
		or die "Failed writing to stats-$tabledate.gz.  Device full?\n";
	}       
    }
    close S;

    $db->do("DROP TABLE $table");
}

