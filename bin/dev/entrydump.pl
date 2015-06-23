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
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}
use LJ::Entry;

my $url = shift;

LJ::DB::no_cache( sub {

    my $entry = LJ::Entry->new_from_url( $url );

    print "entry = $entry\n";
    use Data::Dumper;

    print Dumper( $entry->props, clean($entry->event_orig), clean($entry->event_raw) );
} );


sub clean {
    my $txt = shift;
    $txt =~ s/[^\x20-\x7f]/"[" . sprintf("%02x", ord($&)) . "]"/eg;
    return $txt;
}

