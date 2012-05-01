#!/usr/bin/perl
#

package S2::OutputConsole;

use strict;

sub new {
    my $class = shift;
    my $this = {};
    bless $this, $class;
}

sub write {
    print $_[1];
}

sub writeln {
    print $_[1], "\n";
}

sub newline {
    print "\n";
}

sub flush { }


1;
