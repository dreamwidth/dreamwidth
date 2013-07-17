#!/usr/bin/perl
#

package S2::NodePushStmt;

use strict;
use S2::Node;
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
    return $toker->peek() == $S2::TokenKeyword::PUSH;
}

sub parse {
    my ($class, $toker) = @_;

    my $n = new S2::NodePushStmt;
    $n->setStart($n->requireToken($toker, $S2::TokenKeyword::PUSH));
    $n->addNode($n->{'lhs'} = S2::NodeTerm->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::COMMA);
    $n->addNode($n->{'expr'} = S2::NodeExpr->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::SCOLON);
    return $n;
}

sub check {
    my ($this, $l, $ck) = @_;

    S2::error($this, "Push target is not an assignable value.")
        unless $this->{lhs}->isLValue();

    my $lt = $this->{lhs}->getType($ck);
    S2::error($this, "Push target is not an array.")
        unless $lt->isArrayOf();

    my $rt = $this->{expr}->getType($ck);
    S2::error($this, "Push expression must be a simple type.")
        unless $rt->isSimple();

    S2::error($this, "Type mismatch between push target and expression.")
        unless $lt->baseType() eq $rt->baseType();
}

sub asS2 {
    my ($this, $o) = @_;

    $o->write("push ");
    $this->{'lhs'}->asS2($o);
    $o->write(", ");
    $this->{'expr'}->asS2($o);
}

sub asPerl {
    my ($this, $bp, $o) = @_;

    $o->tabwrite("push(\@{");
    $this->{'lhs'}->asPerl($bp, $o);
    $o->write("}, ");
    $this->{'expr'}->asPerl($bp, $o);
    $o->writeln(");");
}
