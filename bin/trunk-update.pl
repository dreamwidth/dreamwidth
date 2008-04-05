#!/usr/bin/perl

use strict;
use IO::Socket::INET;

unless ($ENV{LJHOME}) {
    die "\$LJHOME not set.";
}
chdir "$ENV{LJHOME}" or die "Failed to chdir to \$LJHOME";

my $cvsreport = "$ENV{LJHOME}/bin/cvsreport.pl";

die "cvsreport.pl missing or unexecutable" unless -x $cvsreport;

require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
die "NO DO NOT RUN THIS IN PRODUCTION" if $LJ::IS_LJCOM_PRODUCTION;


update_svn();
my @files = get_updated_files();
sync();
new_phrases() if  grep { /en.+\.dat/ } @files;
update_db() if  grep { /\.sql/ } @files;
bap() if  grep { /cgi-bin.+\.[pl|pm]/ } @files;


my $updatedfilepath = "$ENV{LJHOME}/logs/trunk-last-updated.txt";
my $updatedfh;
open($updatedfh, ">$updatedfilepath") or return "Could not open file $updatedfilepath: $!\n";
print $updatedfh time();
close $updatedfh;

if (@files) {
    exit 0;
}

exit 1;



sub update_svn {
    system($cvsreport, "-u", "--checkout")
	and die "Failed to run cvsreport.pl with update.";
}

sub get_updated_files {
    my @files = ();
    open(my $cr, '-|', $cvsreport, '-c', '-1') or die "Could not run cvsreport.pl";
    while (my $line = <$cr>) {
	$line =~ s/\s+$//;
	push @files, $line;
    }
    close($cr);

    return @files;
}

sub sync {
    system($cvsreport, "-c", "-s")
	and die "Failed to run cvsreport.pl sync second time.";
}

sub update_db {
    foreach (1..10) {
        my $res = system("bin/upgrading/update-db.pl", "-r", "-p");
        last if $res == 0;

        if ($res & 127 == 9) {
            warn "Killed by kernel (ran out of memory) sleeping and retrying";
            sleep 60;
            next;
        }

        die "Unknown exit state of `update-db.pl -r -p`: $res";
    }

    system("bin/upgrading/update-db.pl", "-r", "--cluster=all")
	and die "Failed to run update-db.pl on all clusters";
}

sub new_phrases {
    my @langs = @_;

    system("bin/upgrading/texttool.pl", "load", @langs)
	and die "Failed to run texttool.pl load @langs";
}

sub bap {
    print "Restarting apache...\n";

    my $sock = IO::Socket::INET->new(PeerAddr => "127.0.0.1:7600")
        or die "Couldn't connect to webnoded (port 7600)\n";

    print $sock "apr\r\n";
    while (my $ln = <$sock>) {
	print "$ln";
	last if $ln =~ /^OK/;
    }
}
