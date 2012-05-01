#!/usr/bin/perl
#

package S2::FilePos;

use strict;

sub new
{
    my ($class, $l, $c) = @_;
    my $this = [ $l, $c ];
    bless $this, $class;
    return $this;
}

sub line { shift->[0]; }
sub col { shift->[1]; }

sub clone
{
    my $this = shift;
    return new S2::FilePos(@$this);
}

sub locationString
{
    my $this = shift;
    return "line $this->[0], column $this->[1]";
}

sub toString
{
    my $this = shift;
    return $this->locationString();
}

1;
