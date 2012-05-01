#!/usr/bin/perl
#

package S2::NodeSum;

use strict;
use S2::Node;
use S2::NodeProduct;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class, $lhs, $op, $rhs) = @_;
    my $node = new S2::Node;
    $node->{'lhs'} = $lhs;
    $node->{'op'} = $op;
    $node->{'rhs'} = $rhs;
    bless $node, $class;
}

sub canStart {
    my ($class, $toker) = @_;
    S2::NodeProduct->canStart($toker);
}

sub parse {
    my ($class, $toker) = @_;

    my $lhs = parse S2::NodeProduct $toker;
    $lhs->skipWhite($toker);

    while ($toker->peek() == $S2::TokenPunct::PLUS ||
           $toker->peek() == $S2::TokenPunct::MINUS) {
        $lhs = parseAnother($toker, $lhs);
    }

    return $lhs;
}

sub parseAnother {
    my ($toker, $lhs) = @_;

    my $n = new S2::NodeSum();

    $n->{'lhs'} = $lhs;
    $n->addNode($n->{'lhs'});

    $n->{'op'} = $toker->peek();
    $n->eatToken($toker);
    $n->skipWhite($toker);

    $n->{'rhs'} = parse S2::NodeProduct $toker;
    $n->addNode($n->{'rhs'});
    $n->skipWhite($toker);

    return $n;
}

sub getType {
    my ($this, $ck, $wanted) = @_;

    my $lt = $this->{'lhs'}->getType($ck, $wanted);
    my $rt = $this->{'rhs'}->getType($ck, $wanted);

    unless ($lt->equals($S2::Type::INT) || 
            $lt->equals($S2::Type::STRING))
    {
        if ($this->{'lhs'}->makeAsString($ck)) {
            $lt = $S2::Type::STRING;
        } else {
            S2::error($this->{'lhs'}, "Left hand side of " . $this->{'op'}->getPunct() . 
                      " operator is " . $lt->toString() . ", not a string or integer");
        }
    }

    unless ($rt->equals($S2::Type::INT) || 
            $rt->equals($S2::Type::STRING))
    {
        if ($this->{'rhs'}->makeAsString($ck)) {
            $rt = $S2::Type::STRING;
        } else {
            S2::error($this->{'rhs'}, "Right hand side of " . $this->{'op'}->getPunct() . 
                      " operator is " . $rt->toString() . ", not a string or integer");
        }
    }

    if ($this->{'op'} == $S2::TokenPunct::MINUS && 
        ($lt->equals($S2::Type::STRING) || 
         $rt->equals($S2::Type::STRING))) {
        S2::error($this->{'rhs'}, "Can't substract strings.");
    }

    if ($lt->equals($S2::Type::STRING) || 
        $rt->equals($S2::Type::STRING)) {
        return $this->{'myType'} = $S2::Type::STRING;
    }

    return $this->{'myType'} = $S2::Type::INT;
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

    if ($this->{'myType'} == $S2::Type::STRING) {
        $o->write(" . ");
    } elsif ($this->{'op'} == $S2::TokenPunct::PLUS) {
        $o->write(" + ");
    } elsif ($this->{'op'} == $S2::TokenPunct::MINUS) {
        $o->write(" - ");
    }
     
    $this->{'rhs'}->asPerl($bp, $o);
}

