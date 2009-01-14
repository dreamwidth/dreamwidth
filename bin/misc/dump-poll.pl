#!/usr/bin/perl

##
## This script dumps all poll data (questions, answers, results, etc) 
## to file <poll_id>.xml
## Usage:  dump-poll.pl <poll_id>
##

use strict;
use warnings;
use lib "$ENV{'LJHOME'}/cgi-bin";
require "$ENV{'LJHOME'}/cgi-bin/ljlib.pl";
use LJ::Poll;

my $id = $ARGV[0] or die "Usage: $0 <poll_id>";
my $filename = "$id.xml";
open my($fh), ">$filename" or die "Can't write to '$filename': $!";
LJ::Poll->new($id)->dump_poll($fh);
$fh->close;



