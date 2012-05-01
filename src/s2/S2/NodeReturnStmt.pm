#!/usr/bin/perl
#

package S2::NodeReturnStmt;

use strict;
use S2::Node;
use S2::NodeExpr;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub canStart {
    my ($class, $toker) = @_;
    return $toker->peek() == $S2::TokenKeyword::RETURN;
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeReturnStmt;
    $n->setStart($n->requireToken($toker, $S2::TokenKeyword::RETURN));

    # optional return expression
    if (S2::NodeExpr->canStart($toker)) {
        $n->addNode($n->{'expr'} = S2::NodeExpr->parse($toker));
    }

    $n->requireToken($toker, $S2::TokenPunct::SCOLON);
    return $n;
}

sub check {
    my ($this, $l, $ck) = @_;

    my $exptype = $ck->getReturnType();
    my $rettype = $this->{'expr'} ?
        $this->{'expr'}->getType($ck, $exptype) : 
        $S2::Type::VOID;

    if ($ck->checkFuncAttr($ck->getInFunction(), "notags")) {
        $this->{'notags_func'} = 1;
    }
    
    unless ($ck->typeIsa($rettype, $exptype)) {
        S2::error($this, "Return type of " . $rettype->toString . " doesn't match expected type of " . $exptype->toString);
      }
}

sub asS2 {
    my ($this, $o) = @_;
    $o->tabwrite("return");
    if ($this->{'expr'}) {
        $o->write(" ");
        $this->{'expr'}->asS2($o);
    }
    $o->writeln(";");
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    $o->tabwrite("return");
    if ($this->{'expr'}) {
        my $need_notags = $bp->untrusted() && $this->{'notags_func'};
        $o->write(" ");
        if ($need_notags) {
            if ($bp->oo) {
                $o->write("S2::Runtime::OO::_notags(");
            }
            else {
                $o->write("S2::notags(");
            }
        }
        $this->{'expr'}->asPerl($bp, $o);
        $o->write(")") if $need_notags;
    }
    $o->writeln(";");
}

