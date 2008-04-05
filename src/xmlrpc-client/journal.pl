#!/usr/bin/perl
#
# Brad's journal client <brad@danga.com>
#

use strict;
use Fcntl;
use POSIX qw(tmpnam);
use XMLRPC::Lite;
use Data::Dumper;
my $CONFFILE = "$ENV{'HOME'}/.journalconf";

unless (-s $CONFFILE) {
    open (C, ">>$CONFFILE"); close C; chmod 0700, $CONFFILE;
    print "\nNo ~/.journalconf config file found.\nFormat: one journal account per line.\n";
    print "Example config for posting to both LiveJournal and Slashdot:\n\n";
    print "servertype=lj username=test password=test host=www.livejournal.com\n";
    print "servertype=slash username=\"some username\" password=linux host=slashdot.org\n";
    print "\n";
    exit 1;
}

my %dispatch;

# LiveJournal support
$dispatch{'lj'} = sub 
{
    my ($acct, $post) = @_;
    my $xmlrpc = new XMLRPC::Lite;
    $xmlrpc->proxy("http://$acct->{'host'}/interface/xmlrpc");
    my @now = localtime();
    my $req = {
	'username' => $acct->{'username'},
	'password' => $acct->{'password'},
	'subject' => $post->{'subject'},
	'event' => $post->{'body'},
	'mode' => 'postevent',
	'security' => $post->{'security'} || "public",
	'year' => $now[5]+1900,
	'mon' => $now[4]+1,
	'day' => $now[3],
	'hour' => $now[2],
	'min' => $now[1],
    };
    foreach (qw(music mood)) {
	next unless $post->{$_};
	$req->{"props"}->{"current_$_"} = $post->{$_};
    }
    my $res = $xmlrpc->call('LJ.XMLRPC.postevent', $req);
    if ($res->fault) { 
	print STDERR "Error posting to LJ server:\n".
	    "  String: " . $res->faultstring . "\n" .
	    "  Code: " . $res->faultcode . "\n";
	return 0;
    }
    return 1;
};

$dispatch{'slash'} = sub
{
    print STDERR "Unimplemented.\n";
    return 0;
};

my $editor = $ENV{'EDITOR'} || "vi";
my $tmpname;
do { $tmpname = tmpnam() }
until sysopen(FH, $tmpname, O_RDWR|O_CREAT|O_EXCL);
END { unlink($tmpname); }

print FH "Subject: \n";
print FH "----\n";
close FH;
chmod $tmpname, 0700;

if (system($editor, $tmpname)) {
    die "Failed to run \$EDITOR\n";
}

my %jdata;
open (J, $tmpname) or die "Can't reopen temp file?";
$jdata{lc($1)} = $2 
    while (scalar(<J>) =~ /^\s*(\S+)\s*:\s*(.+?)\s*\n/);
$jdata{'body'} .= join('',<J>);
$jdata{'body'} =~ s/\s+$//;

open (C, $CONFFILE);
while (<C>) {
    next unless /\S/;
    chomp;
    my %params;
    while (s/(\w+)=(?:([^\"\s]+)|(\"(.+?)\"))//) {
	$params{$1} = $2 || $4;
	
    }
    my $stype = $params{'servertype'};
    die "Unknown server type \"$stype\"\n"
	unless defined $dispatch{$stype};
    die "Error posting to $stype\n"
	unless ($dispatch{$stype}->(\%params, \%jdata));
}
close C;
print "Done.\n";

