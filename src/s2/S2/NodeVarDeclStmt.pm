#!/usr/bin/perl
#

package S2::NodeVarDeclStmt;

use strict;
use S2::Node;
use S2::NodeVarDecl;
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
    my ($this, $toker) = @_;
    return S2::NodeVarDecl->canStart($toker);
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeVarDeclStmt;
    
    $n->addNode($n->{'nvd'} = S2::NodeVarDecl->parse($toker));
    if ($toker->peek() == $S2::TokenPunct::ASSIGN) {
        $n->eatToken($toker);
        $n->addNode($n->{'expr'} = S2::NodeExpr->parse($toker));
    }
    $n->requireToken($toker, $S2::TokenPunct::SCOLON);
    return $n;
}

sub check {
    my ($this, $l, $ck) = @_;

    $this->{'nvd'}->populateScope($ck->getLocalScope());

    # check that the variable type is a known class
    my $t = $this->{'nvd'}->getType();
    my $bt = $t->baseType();

    S2::error($this, "Unknown type or class '$bt'") 
        unless S2::Type::isPrimitive($bt) || $ck->getClass($bt);

    my $vname = $this->{'nvd'}->getName();

    if ($this->{'expr'}) {
        my $et = $this->{'expr'}->getType($ck, $t);
        S2::error($this, "Can't initialize variable '$vname' " .
                  "of type " . $t->toString . " with expression of type " .
                  $et->toString())
            unless $ck->typeIsa($et, $t);
    }

    S2::error($this, "Reserved variable name") if $vname eq "_ctx";
}

sub asS2 {
    my ($this, $o) = @_;
    $o->tabwrite("");
    $this->{'nvd'}->asS2($o);
    if ($this->{'expr'}) {
        $o->write(" = ");
        $this->{'expr'}->asS2($o);
    }
    $o->writeln(";");
}

sub asPerl {
    my ($this, $bp, $o, $opts) = @_;
    $o->tabwrite("") unless ($opts && $opts->{as_expr});
    $this->{'nvd'}->asPerl($bp, $o);
    if ($this->{'expr'}) {
        $o->write(" = ");
        $this->{'expr'}->asPerl($bp, $o);
    } else {
        my $t = $this->{'nvd'}->getType();
        if ($t->equals($S2::Type::STRING)) {
            $o->write(" = \"\"");
        } elsif ($t->equals($S2::Type::BOOL) ||
                 $t->equals($S2::Type::INT)) {
            $o->write(" = 0");
        }
    }
    $o->writeln(";") unless ($opts && $opts->{as_expr});
}


