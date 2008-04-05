#!/usr/bin/perl
#

use strict;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Entry;

my $url = shift;

LJ::no_cache(sub {

my $entry = LJ::Entry->new_from_url($url);

print "entry = $entry\n";
use Data::Dumper;

    print Dumper($entry->props, clean($entry->event_orig), clean($entry->event_raw));
});


sub clean {
    my $txt = shift;
    $txt =~ s/[^\x20-\x7f]/"[" . sprintf("%02x", ord($&)) . "]"/eg;
    return $txt;
}

