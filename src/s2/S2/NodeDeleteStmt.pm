#!/usr/bin/perl
#

package S2::NodeDeleteStmt;

use strict;
use S2::Node;
use S2::NodeVarRef;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $n = new S2::Node;
    bless $n, $class;
}

sub canStart {
    my ($class, $toker) = @_;
    return $toker->peek() == $S2::TokenKeyword::DELETE;
}

sub parse {
    my ($class, $toker) = @_;

    my $n = new S2::NodeDeleteStmt;
    my $t = $toker->peek();

    $n->setStart($n->requireToken($toker, $S2::TokenKeyword::DELETE));
    $n->addNode($n->{'var'} = S2::NodeVarRef->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::SCOLON);

    return $n;
}

sub check {
    my ($this, $l, $ck) = @_;

    # type check the innards, but we don't care what type 
    # actually is.
    $this->{'var'}->getType($ck);

    # but it must be a hash reference
    unless ($this->{'var'}->isHashElement()) {
        S2::error($this, "Delete statement argument is not a hash");
    }
}

sub asS2 {
    my ($this, $o) = @_;
    $o->tabwrite("delete ");
    $this->{'var'}->asS2($o);
    $o->writeln(";");
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    $o->tabwrite("delete ");
    $this->{'var'}->asPerl($bp, $o);
    $o->writeln(";");
}

