#!/usr/bin/perl
#

package S2::NodeVarDecl;

use strict;
use S2::Node;
use S2::NodeNamedType;
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
    return $toker->peek() == $S2::TokenKeyword::VAR;
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeVarDecl;
    
    $n->setStart($n->requireToken($toker, $S2::TokenKeyword::VAR));
    $n->addNode($n->{'nt'} = S2::NodeNamedType->parse($toker));
    return $n;
}

sub getType { shift->{'nt'}->getType; }
sub getName { shift->{'nt'}->getName; }

sub populateScope {
    my ($this, $nb) = @_;  # NodeStmtBlock
    my $name = $this->{'nt'}->getName;
    my $et = $nb->getLocalVar($name);
    S2::error("Can't mask local variable '$name'") if $et;
    $this->{owningScope} = $nb;
    $nb->addLocalVar($name, $this->{'nt'}->getType());
}

sub asS2 {
    my ($this, $o) = @_;
    $o->write("var ");
    $this->{'nt'}->asS2($o);
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    $o->write("my \$" . $this->{'nt'}->getName());
}


