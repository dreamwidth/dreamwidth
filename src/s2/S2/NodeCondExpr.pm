#!/usr/bin/perl
#

package S2::NodeCondExpr;

use strict;
use S2::Node;
use S2::NodeRange;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class, $n) = @_;
    my $node = new S2::Node;
    bless $node, $class;
}

sub canStart {
    my ($class, $toker) = @_;
    S2::NodeRange->canStart($toker);
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeCondExpr;

    $n->{'test_expr'} = parse S2::NodeRange $toker;
    $n->addNode($n->{'test_expr'});

    return $n->{'test_expr'} unless
        $toker->peek() == $S2::TokenPunct::QMARK;

    $n->eatToken($toker);

    $n->{'true_expr'} = parse S2::NodeRange $toker;
    $n->addNode($n->{'true_expr'});
    $n->requireToken($toker, $S2::TokenPunct::COLON);

    $n->{'false_expr'} = parse S2::NodeRange $toker;
    $n->addNode($n->{'false_expr'});

    return $n;
}

sub getType {
    my ($this, $ck) = @_;

    my $ctype = $this->{'test_expr'}->getType($ck);
    unless ($ctype->isBoolable()) {
        S2::error($this, "Conditional expression not of type boolean.");
    }

    my $lt = $this->{'true_expr'}->getType($ck);
    my $rt = $this->{'false_expr'}->getType($ck);
    unless ($lt->equals($rt)) {
        S2::error($this, "Types don't match in conditional expression.");
    }
    return $lt;
}

sub asS2 {
    my ($this, $o) = @_;
    $this->{'test_expr'}->asS2($o);
    $o->write(" ? ");
    $this->{'true_expr'}->asS2($o);
    $o->write(" : ");
    $this->{'false_expr'}->asS2($o);
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    $o->write("(");
    $this->{'test_expr'}->asPerl_bool($bp, $o);
    $o->write(" ? ");
    $this->{'true_expr'}->asPerl($bp, $o);
    $o->write(" : ");
    $this->{'false_expr'}->asPerl($bp, $o);
    $o->write(")");
}

