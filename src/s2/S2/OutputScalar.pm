#!/usr/bin/perl
#

package S2::OutputScalar;

use strict;

sub new {
    my ($class, $scalar) = @_;
    my $ref = [ $scalar ];
    bless $ref, $class;
}

sub write {
    ${$_[0]->[0]} .= $_[1];
}

sub writeln {
    ${$_[0]->[0]} .= $_[1] . "\n";
}

sub newline {
    ${$_[0]->[0]} .= "\n";
}

sub flush { }


1;
