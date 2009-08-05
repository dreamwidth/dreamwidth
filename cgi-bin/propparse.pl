#!/usr/bin/perl
#

package LJ;

$verbose = 0;
@obs = ();

sub xlinkify
{
    my ($a) = $_[0];
    $$a =~ s/\[var\[([A-Z0-9\_]{2,})\]\]/<a href=\"\/developer\/varinfo?$1\">$1<\/a>/g;
    $$a =~ s/\[view\[(\S+?)\]\]/<a href=\"\/developer\/views\#$1\">$1<\/a>/g;
}


1;
