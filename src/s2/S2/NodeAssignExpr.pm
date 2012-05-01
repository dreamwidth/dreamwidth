#!/usr/bin/perl
#

package S2::NodeAssignExpr;

use strict;
use S2::Node;
use S2::NodeCondExpr;
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
    S2::NodeCondExpr->canStart($toker);
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeAssignExpr;

    $n->{'lhs'} = parse S2::NodeCondExpr $toker;
    $n->addNode($n->{'lhs'});

    if ($toker->peek() == $S2::TokenPunct::ASSIGN) {
        $n->{'op'} = $toker->peek();
        $n->eatToken($toker);
    } else {
        return $n->{'lhs'};
    }

    $n->{'rhs'} = parse S2::NodeAssignExpr $toker;
    $n->addNode($n->{'rhs'});

    return $n;
}

sub getType {
    my ($this, $ck, $wanted) = @_;

    my $lt = $this->{'lhs'}->getType($ck, $wanted);
    my $rt = $this->{'rhs'}->getType($ck, $lt);

    if ($lt->isReadOnly()) {
        S2::error($this, "Left-hand side of assignment is a read-only value.");
    }

    if (! $this->{'lhs'}->isa('S2::NodeTerm') ||
        ! $this->{'lhs'}->isLValue()) {
        S2::error($this, "Left-hand side of assignment must be an lvalue.");
    }

    if ($this->{'lhs'}->isBuiltinProperty($ck)) {
        S2::error($this, "Can't assign to built-in properties.");
    }

    return $lt if $ck->typeIsa($rt, $lt);

    # types don't match, but maybe class for left hand side has
    # a constructor which takes a string. 
    if ($rt->equals($S2::Type::STRING) && $ck->isStringCtor($lt)) {
        $rt = $this->{'rhs'}->getType($ck, $lt);  # FIXME: can remove this line?
        return $lt if $lt->equals($rt);
    }

    S2::error($this, "Can't assign type " . $rt->toString . " to " . $lt->toString);
}

sub asS2 {
    my ($this, $o) = @_;
    $this->{'lhs'}->asS2($o);
    if ($this->{'op'}) {
        $o->write(" = ");
        $this->{'rhs'}->asS2($o);
    }
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    die "INTERNAL ERROR: no op?" unless $this->{'op'};

    $this->{'lhs'}->asPerl($bp, $o);

    my $need_notags = $bp->untrusted() && 
        $this->{'lhs'}->isProperty() &&
        $this->{'lhs'}->getType()->equals($S2::Type::STRING);

    $o->write(" = ");
    if ($need_notags) {
        if ($bp->oo) {
            $o->write("S2::Runtime::OO::_notags(");
        }
        else {
            $o->write("S2::notags(");
        }
    }
    $this->{'rhs'}->asPerl($bp, $o);
    $o->write(")") if $need_notags;

}

