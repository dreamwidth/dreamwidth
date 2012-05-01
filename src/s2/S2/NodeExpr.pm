#!/usr/bin/perl
#

package S2::NodeExpr;

use strict;
use S2::Node;
use S2::NodeAssignExpr;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class, $n) = @_;
    my $node = new S2::Node;
    $node->{'expr'} = $n;
    bless $node, $class;
}

sub canStart {
    my ($class, $toker) = @_;
    S2::NodeAssignExpr->canStart($toker);
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeExpr;
    $n->{'expr'} = parse S2::NodeAssignExpr $toker;
    $n->addNode($n->{'expr'});
    return $n;
}

sub asS2 {
    my ($this, $o) = @_;
    $this->{'expr'}->asS2($o);
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    $this->{'expr'}->asPerl($bp, $o);
}

sub getType {
    my ($this, $ck, $wanted) = @_;
    $this->{'expr'}->getType($ck, $wanted);
}

sub makeAsString {
    my ($this, $ck) = @_;
    $this->{'expr'}->makeAsString($ck);
}

sub getExpr {
    shift->{'expr'};
}
