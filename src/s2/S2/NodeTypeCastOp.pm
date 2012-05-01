#!/usr/bin/perl
#

package S2::NodeTypeCastOp;

use strict;
use S2::Node;
use S2::NodeIncExpr;
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
    return S2::NodeIncExpr->canStart($toker);
}

sub parse {
    my ($class, $toker) = @_;

    my $expr = parse S2::NodeIncExpr $toker;
    
    if ($toker->peek() == $S2::TokenKeyword::AS) {
        my $n = new S2::NodeTypeCastOp;
        $n->addNode($expr);
        $n->{'opline'} = $toker->peek()->getFilePos()->line;
        $n->eatToken($toker);
        $n->{expr} = $expr;
        $n->{toClass} = $n->getIdent($toker,1)->getIdent();
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
        S2::error($this->{expr}, "Only objects may be type-casted");
    }
    my $toClass = $this->{toClass};
    
    unless (defined $ck->getClass($toClass)) {
        S2::error($this, "Unknown class '$toClass'");
    }

    # Both upcasting and downcasting are supported, but upcasting
    # is implicit anyway so will rarely be used and is only here
    # for completeness.
    
    my $toType = new S2::Type($toClass);
    if ($ck->typeIsa($t, $toType)) {
        $this->{downcast} = 0;
    }
    elsif ($ck->typeIsa($toType, $t)) {
        $this->{downcast} = 1;
    }
    else {
        S2::error($this, "Cannot cast expression of type '" . $t->toString() .
                         "' to unrelated type '$toClass'");
    }
    
    return $toType;
}

sub asS2 {
    my ($this, $o) = @_;
    $this->{expr}->asS2($o);
    $o->write(" as " . $this->{qClass});
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    
    if (! $this->{downcast}) {
        $this->{expr}->asPerl($bp, $o);
        return;
    }
    
    # For downcasts, need to call function at runtime to ensure the
    # object is of the correct type.
    if ($bp->oo) {
        $o->write("\$_ctx->_downcast_object(");
        $this->{'expr'}->asPerl($bp, $o);
        $o->write(",".$bp->quoteString($this->{toClass}).",\$lay,$this->{opline})");
    }
    else {
        $o->write("S2::downcast_object(\$_ctx,");
        $this->{'expr'}->asPerl($bp, $o);
        $o->write(",".$bp->quoteString($this->{toClass}).",".
                  $bp->getLayerID().",$this->{opline})");
    }
}

