#!/usr/bin/perl
#

package S2::NodeProperty;

use strict;
use S2::Node;
use S2::NodeNamedType;
use S2::NodePropertyPair;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $node = new S2::Node;
    $node->{'nt'} = undef;
    $node->{'pairs'} = [];
    $node->{'builtin'} = 0;
    $node->{'use'} = 0;
    $node->{'hide'} = 0;
    $node->{'uhName'} = undef; # if use or hide, then this is property to use/hide
    bless $node, $class;
}

sub canStart {
    my ($class, $toker) = @_;
    return $toker->peek() == $S2::TokenKeyword::PROPERTY;
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeProperty;
    $n->{'pairs'} = [];

    $n->setStart($n->requireToken($toker, $S2::TokenKeyword::PROPERTY));
    
    if ($toker->peek() == $S2::TokenKeyword::BUILTIN) {
        $n->{'builtin'} = 1;
        $n->eatToken($toker);
    }

    # parse the use/hide case
    if ($toker->peek()->isa('S2::TokenIdent')) {
        my $ident = $toker->peek()->getIdent();
        if ($ident eq "use" || $ident eq "hide") {
            $n->{'use'} = 1 if $ident eq "use";
            $n->{'hide'} = 1 if $ident eq "hide";
            $n->eatToken($toker);

            my $t = $toker->peek();
            unless ($t->isa('S2::TokenIdent')) {
                S2::error($t, "Expecting identifier after $ident");
            }
            
            $n->{'uhName'} = $t->getIdent();
            $n->eatToken($toker);
            $n->requireToken($toker, $S2::TokenPunct::SCOLON);
            return $n;
        }
    }

    $n->addNode($n->{'nt'} = S2::NodeNamedType->parse($toker));
    
    my $t = $toker->peek();
    if ($t == $S2::TokenPunct::SCOLON) {
        $n->eatToken($toker);
        return $n;
    }

    $n->requireToken($toker, $S2::TokenPunct::LBRACE);
    while (S2::NodePropertyPair->canStart($toker)) {
        my $pair = S2::NodePropertyPair->parse($toker);
        push @{$n->{'tokenlist'}}, $pair;
        push @{$n->{'pairs'}}, $pair;
    }
    $n->requireToken($toker, $S2::TokenPunct::RBRACE);

    return $n;
}

sub check {
    my ($this, $l, $ck) = @_;

    if ($this->{'use'}) {
        unless ($l->getType() eq "layout") {
            S2::error($this, "Can't declare property usage in non-layout layer");
        }
        unless ($ck->propertyType($this->{'uhName'})) {
            S2::error($this, "Can't declare usage of non-existent property");
        }
        return;
    }

    if ($this->{'hide'}) {
        unless ($ck->propertyType($this->{'uhName'})) {
            S2::error($this, "Can't hide non-existent property");
        }
        return;
    }

    my $name = $this->{'nt'}->getName();
    my $type = $this->{'nt'}->getType();

    if ($l->getType() eq "i18n") {
        # FIXME: as a special case, allow an i18n layer to
        # to override the 'des' property of a property, so
        # that stuff can be translated
        return;
    }

    # only core and layout layers can define properties
    unless ($l->isCoreOrLayout()) {
        S2::error($this, "Only core and layout layers can define new properties.");
    }

    # make sure they aren't overriding a property from a lower layer
    my $existing = $ck->propertyType($name);
    if ($existing && ! $type->equals($existing)) {
      S2::error($this, "Can't override property '$name' of type " .
                $existing->toString . " with new type " . 
                $type->toString . ".");
    }

    my $basetype = $type->baseType;
    if (! S2::Type::isPrimitive($basetype) && ! defined $ck->getClass($basetype)) {
        S2::error($this, "Can't define a property of an unknown class");
    }

    # all is well, so register this property with its type
    $ck->addProperty($name, $type, $this->{'builtin'});
}

sub asS2 {
    my ($this, $o) = @_;
    $o->tabwrite("property ");
    $o->write("builtin ") if $this->{'builtin'};
    if ($this->{'use'} || $this->{'hide'}) {
        $o->write("use ") if $this->{'use'};
        $o->write("hide ") if $this->{'hide'};
        $o->writeln("$this->{'uhName'};");
        return;
    }
    if (@{$this->{'pairs'}}) {
        $o->writeln(" {");
        $o->tabIn();
        foreach my $pp (@{$this->{'pairs'}}) {
            $pp->asS2($o);
        }
        $o->tabOut();
        $o->writeln("}");
    } else {
        $o->writeln(";");
    }
}

sub getName {
    my $this = shift;
    $this->{'uhName'} || $this->{'nt'}->getName();
}

sub asPerl {
    my ($this, $bp, $o) = @_;

    if ($this->{'use'}) {
        if ($bp->oo) {
            $o->tabwriteln("\$lay->register_property_use(".$bp->quoteString($this->{'uhName'}).");");
        }
        else {
            $o->tabwriteln("register_property_use(" .
                           $bp->getLayerIDString() . "," .
                           $bp->quoteString($this->{'uhName'}) . ");");
        }
        return;
    }

    if ($this->{'hide'}) {
        if ($bp->oo) {
            $o->tabwriteln("\$lay->register_property_hide(".$bp->quoteString($this->{'uhName'}).");");
        }
        else {
            $o->tabwriteln("register_property_hide(" .
                           $bp->getLayerIDString() . "," .
                           $bp->quoteString($this->{'uhName'}) . ");");
        }
        return;
    }

    if ($bp->oo) {
        $o->tabwrite("\$lay->register_property(");
    }
    else {
        $o->tabwrite("register_property(".$bp->getLayerIDString().",");
    }
    
    $o->writeln($bp->quoteString($this->{'nt'}->getName()) . ",{");
    $o->tabIn();
    $o->tabwriteln("\"type\"=>" . $bp->quoteString($this->{'nt'}->getType->toString) . ",");
    foreach my $pp (@{$this->{'pairs'}}) {
        $o->tabwriteln($bp->quoteString($pp->getKey()) . "=>" .
                       $bp->quoteString($pp->getVal()) . ",");
    }    
    $o->tabOut();
    $o->writeln("});");
}
