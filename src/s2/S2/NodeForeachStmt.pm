#!/usr/bin/perl
#

package S2::NodeForeachStmt;

use strict;
use S2::Node;
use S2::NodeVarDecl;
use S2::NodeVarRef;
use S2::NodeExpr;
use S2::NodeStmtBlock;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $n = new S2::Node;
    bless $n, $class;
}

sub canStart {
    my ($class, $toker) = @_;
    return $toker->peek() == $S2::TokenKeyword::FOREACH
}

sub parse {
    my ($class, $toker) = @_;

    my $n = new S2::NodeForeachStmt;
    $n->setStart($n->requireToken($toker, $S2::TokenKeyword::FOREACH));

    if (S2::NodeVarDecl->canStart($toker)) {
        $n->addNode($n->{'vardecl'} = S2::NodeVarDecl->parse($toker));
    } else {
        $n->addNode($n->{'varref'} = S2::NodeVarRef->parse($toker));
    }

    # expression in parenthesis representing an array to iterate over:
    $n->requireToken($toker, $S2::TokenPunct::LPAREN);
    $n->addNode($n->{'listexpr'} = S2::NodeExpr->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::RPAREN);

    # and what to do on each element
    $n->addNode($n->{'stmts'} = S2::NodeStmtBlock->parse($toker));

    return $n;
}

sub check {
    my ($this, $l, $ck) = @_;

    my $ltype = $this->{'listexpr'}->getType($ck);

    if ($ltype->isHashOf()) {
        $this->{'isHash'} = 1;
    } elsif ($ltype->equals($S2::Type::STRING)) {
        $this->{'isString'} = 1;
    } elsif (! $ltype->isArrayOf()) {
        S2::error($this, "Must use an array, hash, or string in a foreach");
    }

    my $itype;
    if ($this->{'vardecl'}) {
        $this->{'vardecl'}->populateScope($this->{'stmts'});
        $itype = $this->{'vardecl'}->getType();
    }
    $itype = $this->{'varref'}->getType($ck) if $this->{'varref'};

    if ($this->{'isHash'}) {
        unless ($itype->equals($S2::Type::STRING) ||
                $itype->equals($S2::Type::INT)) {
            S2::error($this, "Foreach iteration variable must be a ".
                      "string or int when interating over the keys ".
                      "in a hash");
        }
    } elsif ($this->{'isString'}) {
        unless ($itype->equals($S2::Type::STRING)) {
            S2::error($this, "Foreach iteration variable must be a ".
                      "string when interating over the characters ".
                      "in a string");
        }
    } else {
        # iter type must be the same as the list type minus
        # the final array ref
        
        # figure out the desired type
        my $dtype = $ltype->clone();
        $dtype->removeMod();

        unless ($dtype->equals($itype)) {
            S2::error("Foreach iteration variable is of type ".
                      $itype->toString . ", not the expected type of ".
                      $dtype->toString);
        }
    }

    $ck->pushLocalBlock($this->{'stmts'});
    $ck->pushBreakable($this->{'stmts'});
    $this->{'stmts'}->check($l, $ck);
    $ck->popBreakable($this->{'stmts'});
    $ck->popLocalBlock();
}

sub asS2 {
    my ($this, $o) = @_;
    die "unported";
}

sub asPerl {
    my ($this, $bp, $o) = @_;

    $o->tabwrite("foreach ");
    $this->{'vardecl'}->asPerl($bp, $o) if $this->{'vardecl'};
    $this->{'varref'}->asPerl($bp, $o) if $this->{'varref'};
    if ($this->{'isHash'}) {
        $o->write(" (keys %{");
    } elsif ($this->{'isString'}) {
        if ($bp->oo) {
            $o->write(" (S2::Runtime::OO::_get_characters(");
        }
        else {
            $o->write(" (S2::get_characters(");
        }
    } else {
        $o->write(" (\@{");
    }

    $this->{'listexpr'}->asPerl($bp, $o);

    if ($this->{'isString'}) {
        $o->write(")) ");
    } else {
        $o->write("}) ");
    }

    $this->{'stmts'}->asPerl($bp, $o);
    $o->newline();
}

