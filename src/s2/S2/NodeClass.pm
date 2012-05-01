#!/usr/bin/perl
#

package S2::NodeClass;

use strict;
use S2::Node;
use S2::NodeClassVarDecl;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $node = new S2::Node;
    $node->{'vars'} = [];
    $node->{'functions'} = [];
    $node->{'varType'} = {};
    $node->{'funcType'} = {};
    bless $node, $class;
}

sub cleanForFreeze {
    my $this = shift;
    delete $this->{'tokenlist'};
    delete $this->{'docstring'};
    foreach (@{$this->{'functions'}}) { $_->cleanForFreeze(); }
    foreach (@{$this->{'vars'}}) { $_->cleanForFreeze(); }
}

sub canStart {
    my ($class, $toker) = @_;
    return $toker->peek() == $S2::TokenKeyword::CLASS;
}

sub parse {
    my ($class, $toker, $isDecl) = @_;
    my $n = new S2::NodeClass;

    # get the function keyword
    $n->setStart($n->requireToken($toker, $S2::TokenKeyword::CLASS));

    $n->{'name'} = $n->getIdent($toker);
    
    if ($toker->peek() == $S2::TokenKeyword::EXTENDS) {
        $n->eatToken($toker);
        $n->{'parentName'} = $n->getIdent($toker);
    }

    # docstring
    if ($toker->peek()->isa('S2::TokenStringLiteral')) {
        my $t = $n->eatToken($toker);
        $n->{'docstring'} = $t->getString();
    }

    $n->requireToken($toker, $S2::TokenPunct::LBRACE);

    my $t;
    while (($t = $toker->peek()) && $t->isa('S2::TokenKeyword')) {
        if ($t == $S2::TokenKeyword::VAR) {
            my $ncvd = parse S2::NodeClassVarDecl $toker;
            push @{$n->{'vars'}}, $ncvd;
            $n->addNode($ncvd);
        } elsif ($t == $S2::TokenKeyword::FUNCTION) {
            my $nm = parse S2::NodeFunction $toker, 1;
            push @{$n->{'functions'}}, $nm;
            $n->addNode($nm);
        } else {
            S2::error($t, "Unexpected keyword ".$t->getIdent());
        }
    }
    $n->requireToken($toker, $S2::TokenPunct::RBRACE);
    return $n;
}

sub getName { shift->{'name'}->getIdent(); }

sub getParentName { 
    my $this = shift;
    return undef unless $this->{'parentName'};
    return $this->{'parentName'}->getIdent();
}

sub getFunctionType {
    my ($this, $funcID) = @_;
    my $t = $this->{'funcType'}->{$funcID};
    return $t if $t;
    return undef unless $this->{'parentClass'};
    return $this->{'parentClass'}->getFunctionType($funcID);
}

sub getFunctionDeclClass {
    my ($this, $funcID) = @_;
    my $t = $this->{'funcType'}->{$funcID};
    return $this if $t;
    return undef unless $this->{'parentClass'};
    return $this->{'parentClass'}->getFunctionDeclClass($funcID);
}

sub getMemberType {
    my ($this, $mem) = @_;
    my $t = $this->{'varType'}->{$mem};
    return $t if $t;
    return undef unless $this->{'parentClass'};
    return $this->{'parentClass'}->getMemberType($mem);
}

sub getMemberDeclClass {
    my ($this, $mem) = @_;
    my $t = $this->{'varType'}->{$mem};
    return $this if $t;
    return undef unless $this->{'parentClass'};
    return $this->{'parentClass'}->getMemberDeclClass($mem);
}

sub getDerClasses {
    my ($this, $l, $depth) = @_;
    $depth ||= 0; $l ||= [];
    my $myname = $this->getName();
    push @$l, { 'nc' => $this, 'dist' => $depth};
    foreach my $cname (@{$this->{'ck'}->getDerClasses($myname)}) {
        my $c = $this->{'ck'}->getClass($cname);
        $c->getDerClasses($l, $depth+1);
    }
    return $l;
}

sub check {
    my ($this, $l, $ck) = @_;

    # keep a reference to the checker for later
    $this->{'ck'} = $ck;

    # can't declare classes inside of a layer if functions
    # have already been declared or defined.
    if ($ck->getHitFunction()) {
        S2::error($this, "Can't declare a class inside a layer ".
                  "file after functions have been defined");
    }

    # if this is an extended class, make sure parent class exists
    $this->{'parentClass'} = undef;
    my $pname = $this->getParentName();
    if (defined $pname) {
        $this->{'parentClass'} = $ck->getClass($pname);
        unless ($this->{'parentClass'}) {
            S2::error($this, "Can't extend non-existent class '$pname'");
        }
    }

    # make sure the class isn't already defined.
    my $cname = $this->{'name'}->getIdent();
    S2::error($this, "Can't redeclare class '$cname'") if $ck->getClass($cname);

    # register all var and function declarations in hash & check for both
    # duplicates and masking of parent class's declarations

    # register self.  this needs to be done before checking member
    # variables so we can have members of our own type.
    $ck->addClass($cname, $this);

    # member vars
    foreach my $nnt (@{$this->{'vars'}}) {
        my $readonly = $nnt->isReadOnly();
        my $vn = $nnt->getName();
        my $vt = $nnt->getType();
        my $et = $this->getMemberType($vn);
        if ($et) {
            my $oc = $this->getMemberDeclClass($vn);
            S2::error($nnt, "Can't declare the variable '$vn' ".
                      "as '" . $vt->toString . "' in class '$cname' because it's ".
                      "already defined in class '". $oc->getName() ."' as ".
                      "type '". $et->toString ."'.");
        }

        # check to see if type exists
        unless ($ck->isValidType($vt)) {
            S2::error($nnt, "Can't declare member variable '$vn' ".
                      "as unknown type '". $vt->toString ."' in class '$cname'");
        }
        
        $vt->setReadOnly($readonly);
        $this->{'varType'}->{$vn} = $vt;  # register member variable
    }

    # all parent class functions need to be inherited:
    $this->registerFunctions($ck, $cname);
}

sub registerFunctions {
    my ($this, $ck, $clas) = @_;

    # register parent's functions first.
    if ($this->{'parentClass'}) {
        $this->{'parentClass'}->registerFunctions($ck, $clas);
    }

    # now do our own
    foreach my $nf (@{$this->{'functions'}}) {
        my $rettype = $nf->getReturnType();
        $nf->registerFunction($ck, $clas);
    }
}


sub asS2 {
    my ($this, $o) = @_;
    die "not done";
}

sub asPerl {
    my ($this, $bp, $o) = @_;

    if ($bp->oo) {
        $o->tabwriteln("\$lay->register_class(".$bp->quoteString($this->getName()).", {");
    }
    else {
        $o->tabwriteln("register_class(" . $bp->getLayerIDString() .
                       ", " . $bp->quoteString($this->getName()) . ", {");
    }
    
    $o->tabIn();
    if ($this->{'parentName'}) {
        $o->tabwriteln("'parent' => " . $bp->quoteString($this->getParentName()) . ",");
    }
    if ($this->{'docstring'}) {
        $o->tabwriteln("'docstring' => " . $bp->quoteString($this->{'docstring'}) . ",");
    }

    # vars
    $o->tabwriteln("'vars' => {");
    $o->tabIn();
    foreach my $nnt (@{$this->{'vars'}}) {
        my $vn = $nnt->getName();
        my $vt = $nnt->getType();
        my $et = $this->getMemberType($vn);
        $o->tabwrite($bp->quoteString($vn) . " => { 'type' => " . $bp->quoteString($vt->toString()));
        if ($vt->isReadOnly()) {
            $o->write(", 'readonly' => 1");
        }
        if ($nnt->getDocString()) {
            $o->write(", 'docstring' => " . $bp->quoteString($nnt->getDocString()));
        }
        $o->writeln(" },");
    }        
    $o->tabOut();
    $o->tabwriteln("},");

    # methods
    $o->tabwriteln("'funcs' => {");
    $o->tabIn();
    foreach my $nf (@{$this->{'functions'}}) {
        my $name = $nf->getName();
        my $nfo = $nf->getFormals();
        my $rt = $nf->getReturnType();
        $o->tabwrite($bp->quoteString($name . ($nfo ? $nfo->toString() : "()"))
                                      . " => { 'returntype' => " 
                                      . $bp->quoteString($rt->toString()));
        if ($nf->getDocString()) {
            $o->write(", 'docstring' => " . $bp->quoteString($nf->getDocString()));
        }
        if (my $attrs = $nf->attrsJoined) {
            $o->write(", 'attrs' => " . $bp->quoteString($attrs));
        }
        $o->writeln(" },");
    }        
    $o->tabOut();
    $o->tabwriteln("},");
        
    $o->tabOut();
    $o->tabwriteln("});");
}

__END__


