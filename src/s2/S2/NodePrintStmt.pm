#!/usr/bin/perl
#

package S2::NodePrintStmt;

use strict;
use S2::Node;
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
    my $p = $toker->peek();
    return
        $p->isa('S2::TokenStringLiteral') ||
        $p == $S2::TokenKeyword::PRINT ||
        $p == $S2::TokenKeyword::PRINTLN;
}

sub parse {
    my ($class, $toker) = @_;

    my $n = new S2::NodePrintStmt;
    my $t = $toker->peek();

    if ($t == $S2::TokenKeyword::PRINT) {
        $n->setStart($n->eatToken($toker));
    }
    if ($t == $S2::TokenKeyword::PRINTLN) {
        $n->setStart($n->eatToken($toker));
        $n->{'doNewline'} = 1;
    }

    $t = $toker->peek();
    if ($t->isa("S2::TokenIdent") && $t->getIdent() eq "safe") {
        $n->{'safe'} = 1;
        $n->eatToken($toker);
    }

    $n->addNode($n->{'expr'} = S2::NodeExpr->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::SCOLON);
    return $n;
}

sub check {
    my ($this, $l, $ck) = @_;
    my $t = $this->{'expr'}->getType($ck);
    return if $t->equals($S2::Type::INT) ||
        $t->equals($S2::Type::STRING);
    unless ($this->{'expr'}->makeAsString($ck)) {
        S2::error($this, "Print statement must print an expression of type int or string, not " .
                  $t->toString);
    }
}

sub asS2 {
    my ($this, $o) = @_;
    $o->tabwrite($this->{'doNewline'} ? "println " : "print ");
    $this->{'expr'}->asS2($o);
    $o->writeln(";");
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    if ($bp->oo) {
        if ($bp->untrusted() || $this->{'safe'}) {
            $o->tabwrite("\$_ctx->_print_safe->(");
        } else {
            $o->tabwrite("\$_ctx->_print(");
        }
    }
    else {
        if ($bp->untrusted() || $this->{'safe'}) {
            $o->tabwrite("\$S2::pout_s->(");
        } else {
            $o->tabwrite("\$S2::pout->(");
        }
    }
    $this->{'expr'}->asPerl($bp, $o);
    $o->write(" . \"\\n\"") if $this->{'doNewline'};
    $o->writeln(");");
}

