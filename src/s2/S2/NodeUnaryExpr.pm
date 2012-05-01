#!/usr/bin/perl
#

package S2::NodeUnaryExpr;

use strict;
use S2::Node;
use S2::NodeInstanceOf;
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
    return $toker->peek() == $S2::TokenPunct::MINUS ||
        $toker->peek() == $S2::TokenPunct::NOT ||
        S2::NodeInstanceOf->canStart($toker);
}

sub parse {
    my ($class, $toker) = @_;

    my $n = new S2::NodeUnaryExpr();

    if ($toker->peek() == $S2::TokenPunct::MINUS) {
        $n->{'bNegative'} = 1;
        $n->eatToken($toker);
    } elsif ($toker->peek() == $S2::TokenKeyword::NOT) {
        $n->{'bNot'} = 1;
        $n->eatToken($toker);
    }

    my $expr = parse S2::NodeInstanceOf $toker;
    
    if ($n->{'bNegative'} || $n->{'bNot'}) {
        $n->{'expr'} = $expr;
        $n->addNode($n->{'expr'});
        return $n;
    }

    return $expr;
}

sub getType {
    my ($this, $ck, $wanted) = @_;

    my $t = $this->{'expr'}->getType($ck);

    if ($this->{'bNegative'}) {
        unless ($t->equals($S2::Type::INT)) {
            S2::error($this->{'expr'}, "Can't use unary minus on non-integer.");
        }
        return $S2::Type::INT;
    }
    if ($this->{'bNot'}) {
        unless ($t->equals($S2::Type::BOOL)) {
            S2::error($this->{'expr'}, "Can't use negation operator on boolean-integer.");
        }
        return $S2::Type::BOOL;
    }
    return undef
}

sub asS2 {
    my ($this, $o) = @_;
    if ($this->{'bNot'}) { $o->write("not "); }
    if ($this->{'bNegative'}) { $o->write("-"); }
    $this->{'expr'}->asS2($o);
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    if ($this->{'bNot'}) { $o->write("! "); }
    if ($this->{'bNegative'}) { $o->write("-"); }
    $this->{'expr'}->asPerl($bp, $o);
}

