#!/usr/bin/perl
#

package S2::NodeEqExpr;

use strict;
use S2::Node;
use S2::NodeRelExpr;
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
    S2::NodeRelExpr->canStart($toker);
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeEqExpr;

    $n->{'lhs'} = parse S2::NodeRelExpr $toker;
    $n->addNode($n->{'lhs'});

    return $n->{'lhs'} unless
        $toker->peek() == $S2::TokenPunct::EQ ||
        $toker->peek() == $S2::TokenPunct::NE;

    $n->{'op'} = $toker->peek();
    $n->eatToken($toker);

    $n->{'rhs'} = parse S2::NodeRelExpr $toker;
    $n->addNode($n->{'rhs'});
    $n->skipWhite($toker);

    return $n;
}

sub getType {
    my ($this, $ck) = @_;

    my $lt = $this->{'lhs'}->getType($ck);
    my $rt = $this->{'rhs'}->getType($ck);

    if (! $lt->equals($rt)) {
        S2::error($this, "The types of the left and right hand side of " .
                  "equality test expression don't match.");
    }

    $this->{'myType'} = $lt;
    
    return $S2::Type::BOOL if $lt->isPrimitive();

    S2::error($this, "Only bool, string, and int types can be tested for equality.");
}

sub asS2 {
    my ($this, $o) = @_;
    $this->{'lhs'}->asS2($o);
    $o->write(" " . $this->{'op'}->getPunct() . " ");
    $this->{'rhs'}->asS2($o);
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    $this->{'lhs'}->asPerl($bp, $o);
    if ($this->{'op'} == $S2::TokenPunct::EQ) {
        if ($this->{'myType'}->equals($S2::Type::STRING)) {
            $o->write(" eq ");
        } else {
            $o->write(" == ");
        }
    } else {
        if ($this->{'myType'}->equals($S2::Type::STRING)) {
            $o->write(" ne ");
        } else {
            $o->write(" != ");
        }
    }
    $this->{'rhs'}->asPerl($bp, $o);
}

