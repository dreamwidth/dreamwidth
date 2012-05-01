#!/usr/bin/perl
#

package S2::NodeRelExpr;

use strict;
use S2::Node;
use S2::NodeSum;
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
    S2::NodeSum->canStart($toker);
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeRelExpr;

    $n->{'lhs'} = parse S2::NodeSum $toker;
    $n->addNode($n->{'lhs'});

    return $n->{'lhs'} unless
        $toker->peek() == $S2::TokenPunct::LT ||
        $toker->peek() == $S2::TokenPunct::LTE ||
        $toker->peek() == $S2::TokenPunct::GT ||
        $toker->peek() == $S2::TokenPunct::GTE;

    $n->{'op'} = $toker->peek();
    $n->eatToken($toker);

    $n->{'rhs'} = parse S2::NodeSum $toker;
    $n->addNode($n->{'rhs'});

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

    if ($lt->equals($S2::Type::STRING) ||
        $lt->equals($S2::Type::INT)) {
        $this->{'myType'} = $lt;
        return $S2::Type::BOOL;
    }

    S2::error($this, "Only string and int types can be compared>");
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

    if ($this->{'op'} == $S2::TokenPunct::LT) {
        if ($this->{'myType'}->equals($S2::Type::STRING)) {
            $o->write(" lt ");
        } else {
            $o->write(" < ");
        }
    } elsif ($this->{'op'} == $S2::TokenPunct::LTE) {
        if ($this->{'myType'}->equals($S2::Type::STRING)) {
            $o->write(" le ");
        } else {
            $o->write(" <= ");
        }
    } elsif ($this->{'op'} == $S2::TokenPunct::GT) {
        if ($this->{'myType'}->equals($S2::Type::STRING)) {
            $o->write(" gt ");
        } else {
            $o->write(" > ");
        }
    } elsif ($this->{'op'} == $S2::TokenPunct::GTE) {
        if ($this->{'myType'}->equals($S2::Type::STRING)) {
            $o->write(" ge ");
        } else {
            $o->write(" >= ");
        }
    }
    
    $this->{'rhs'}->asPerl($bp, $o);
}

