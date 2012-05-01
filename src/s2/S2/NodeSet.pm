#!/usr/bin/perl
#

package S2::NodeSet;

use strict;
use S2::Node;
use S2::NodeExpr;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $node = new S2::Node;
    bless $node, $class;
}

sub canStart {
    my ($class, $toker) = @_;
    return $toker->peek() == $S2::TokenKeyword::SET;
}

sub parse {
    my ($class, $toker) = @_;

    my $nkey; # NodeText
    my $ns = new S2::NodeSet;

    $ns->setStart($ns->requireToken($toker, $S2::TokenKeyword::SET));
    
    $nkey = parse S2::NodeText $toker;
    $ns->addNode($nkey);
    $ns->{'key'} = $nkey->getText();

    $ns->requireToken($toker, $S2::TokenPunct::ASSIGN);

    $ns->{'value'} = parse S2::NodeExpr $toker;
    $ns->addNode($ns->{'value'});
    
    $ns->requireToken($toker, $S2::TokenPunct::SCOLON);
    return $ns;
}


sub asS2 {
    my ($this, $o) = @_;
    $o->tabwrite("set ");
    $o->write(S2::Backend->quoteString($this->{'key'}));
    $o->write(" = ");
    $this->{'value'}->asS2($o);
    $o->writeln(";");
}

sub check {
    my ($this, $l, $ck) = @_;

    my $ltype = $ck->propertyType($this->{'key'});
    $ck->setInFunction(0);

    unless ($ltype) {
        S2::error($this, "Can't set non-existent property '$this->{'key'}'");
    }

    my $rtype = $this->{'value'}->getType($ck, $ltype);
    
    unless ($ltype->equals($rtype)) {
        my $lname = $ltype->toString;
        my $rname = $rtype->toString;
        S2::error($this, "Property value is of wrong type.  Expecting $lname but got $rname.");
    }

    if ($ck->propertyBuiltin($this->{'key'})) {
        S2::error($this, "Can't set built-in properties");
    }

    # simple case... assigning a primitive
    if ($ltype->isPrimitive()) {
        # TODO: check that value.isLiteral()
        # TODO: check value's type matches
        return;
    }

    my $base = new S2::Type $ltype->baseType();
    if ($base->isPrimitive()) {
        return;
    } elsif (! defined $ck->getClass($ltype->baseType())) {
        S2::error($this, "Can't set property of unknown type");
    }
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    
    if ($bp->oo) {
        $o->tabwrite("\$lay->register_set(".$bp->quoteString($this->{'key'}).",");
    }
    else {
        $o->tabwrite("register_set(" .
                     $bp->getLayerIDString() . "," .
                     $bp->quoteString($this->{'key'}) . ",");
    }
    $this->{'value'}->asPerl($bp, $o);
    $o->writeln(");");
    return;
}
