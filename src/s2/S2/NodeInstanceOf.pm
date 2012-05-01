#!/usr/bin/perl
#

package S2::NodeInstanceOf;

use strict;
use S2::Node;
use S2::NodeTypeCastOp;
use S2::TokenPunct;
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
    return S2::NodeTypeCastOp->canStart($toker);
}

sub parse {
    my ($class, $toker) = @_;

    my $expr = parse S2::NodeTypeCastOp $toker;
    
    if ($toker->peek() == $S2::TokenKeyword::INSTANCEOF || $toker->peek() == $S2::TokenKeyword::ISA) {
        my $n = new S2::NodeInstanceOf;
        $n->addNode($expr);
        $n->{'opline'} = $toker->peek()->getFilePos()->line;
        $n->{exact} = ($toker->peek() == $S2::TokenKeyword::INSTANCEOF);
        $n->eatToken($toker);
        $n->{expr} = $expr;
        $n->{qClass} = $n->getIdent($toker,1)->getIdent();
        return $n;
    }
    else {
        return $expr;
    }
}

sub getType {
    my ($this, $ck, $wanted) = @_;
    my $t = $this->{expr}->getType($ck);

    if ($t->isPrimitive() || ! $t->isSimple()) {
        S2::error($this->{expr}, ($this->{exact} ? "instanceof" : "isa") .
                                 " may only be used on objects");
    }
    unless ($ck->getClass($this->{qClass})) {
        S2::error($this, "Unknown class '".$this->{qClass}."'");
    }

    return $S2::Type::BOOL;
}

sub asS2 {
    my ($this, $o) = @_;
    $this->{expr}->asS2($o);
    $o->write(" " . ($this->{exact} ? "instanceof" : "isa") . " " . $this->{qClass});
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    
    if ($this->{exact}) {
        $o->write("((");
        $this->{'expr'}->asPerl($bp, $o);
        $o->write(")->{_type} eq ".$bp->quoteString($this->{qClass}).")");
    }
    else {
        if ($bp->oo) {
            $o->write("\$_ctx->_object_isa(");
        }
        else {
            $o->write("S2::object_isa(\$_ctx,");
        }
        $this->{'expr'}->asPerl($bp, $o);
        $o->write(",".$bp->quoteString($this->{qClass}).")");
    }
}

