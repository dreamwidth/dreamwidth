#!/usr/bin/perl
#

package S2::NodeWhileStmt;

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
    return $toker->peek() == $S2::TokenKeyword::WHILE;
}

sub parse {
    my ($class, $toker) = @_;

    my $n = new S2::NodeWhileStmt;
    $n->setStart($n->requireToken($toker, $S2::TokenKeyword::WHILE));

    $n->requireToken($toker, $S2::TokenPunct::LPAREN);
    $n->addNode($n->{'expr'} = S2::NodeExpr->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::RPAREN);

    $n->addNode($n->{'stmts'} = S2::NodeStmtBlock->parse($toker));

    return $n;
}

sub check {
    my ($this, $l, $ck) = @_;
    
    S2::error("While loops are not supported") if ($ck->crippledFlowControl());

    my $ltype = $this->{'expr'}->getType($ck);
    S2::error($this, "Non-boolean while loop expression") unless $ltype->isBoolable();

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

    $o->tabwrite("while (");
    $this->{'expr'}->asPerl($bp, $o);
    $o->write(") ");

    $this->{'stmts'}->asPerl($bp, $o);
    $o->newline();
}

