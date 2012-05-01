#!/usr/bin/perl
#

package S2::NodeUnnecessary;

use strict;
use S2::Node;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $node = new S2::Node;
    bless $node, $class;
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeUnnecessary;
    $n->skipWhite($toker);
    return $n;
}

sub canStart {
    my ($class, $toker) = @_;
    return ! $toker->peek()->isNecessary();
}

sub asS2 {
    my ($this, $o) = @_;
    # do nothing when making the canonical S2 (the
    # nodes write their whitespace)
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    # do nothing when making the perl output
}

sub check {
    my ($this, $l, $ck) = @_;
    # nothing can be wrong with whitespace and comments
}

