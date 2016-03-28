#!/usr/bin/perl
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

##
## This script dumps all poll data (questions, answers, results, etc)
## to file <poll_id>.xml
## Usage:  dump-poll.pl <poll_id>
##

use strict;
use warnings;
BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}
use LJ::Poll;

my $id = $ARGV[0] or die "Usage: $0 <poll_id>";
my $filename = "$id.xml";
open my($fh), ">$filename" or die "Can't write to '$filename': $!";
LJ::Poll->new($id)->dump_poll($fh);
$fh->close;



