#!/usr/bin/perl
#

package S2::NodeExprStmt;

use strict;
use S2::Node;
use S2::NodeExpr;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $node = new S2::Node;
    bless $node, $class;
}

sub canStart {
    my ($this, $toker) = @_;
    return S2::NodeExpr->canStart($toker);
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeExprStmt;
    $n->addNode($n->{'expr'} = S2::NodeExpr->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::SCOLON);
    return $n;
}

sub check {
    my ($this, $l, $ck) = @_;
    $this->{'expr'}->getType($ck);
}

sub asS2 {
    my ($this, $o) = @_;
    $o->tabwrite("");
    $this->{'expr'}->asS2($o);
    $o->writeln(";");
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    $o->tabwrite("");
    $this->{'expr'}->asPerl($bp, $o);
    $o->writeln(";");
}


