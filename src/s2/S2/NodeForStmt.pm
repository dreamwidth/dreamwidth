#!/usr/bin/perl
#

package S2::NodeForStmt;

use strict;
use S2::Node;
use S2::NodeVarDeclStmt;
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
    return $toker->peek() == $S2::TokenKeyword::FOR;
}

sub parse {
    my ($class, $toker) = @_;

    # for (<vardecl|expr>; <expr>; <expr>) <stmtblock>

    my $n = new S2::NodeForStmt;
    $n->setStart($n->requireToken($toker, $S2::TokenKeyword::FOR));

    $n->requireToken($toker, $S2::TokenPunct::LPAREN);

    if (S2::NodeVarDeclStmt->canStart($toker)) {
        # This is a bit sick; borrow the code for parsing vardecl statements...
        # we want a semicolon on the end but vardeclstmt will eat it so we
        # just skip over it in this case.
        $n->addNode($n->{'vardecl'} = S2::NodeVarDeclStmt->parse($toker));
    } else {
        $n->addNode($n->{'initexpr'} = S2::NodeExpr->parse($toker));
        $n->requireToken($toker, $S2::TokenPunct::SCOLON);
    }

    $n->addNode($n->{'condexpr'} = S2::NodeExpr->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::SCOLON);
    $n->addNode($n->{'iterexpr'} = S2::NodeExpr->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::RPAREN);

    # and what to do on each element
    $n->addNode($n->{'stmts'} = S2::NodeStmtBlock->parse($toker));

    return $n;
}

sub check {
    my ($this, $l, $ck) = @_;

    S2::error("For loops are not supported") if ($ck->crippledFlowControl());

    # Just call getType on these in order to check them. We don't really care what the type is.

    if ($this->{'vardecl'}) {
        $this->{'vardecl'}->{'nvd'}->populateScope($this->{'stmts'});
        $this->{'vardecl'}->{'nvd'}->getType();
    }
    else {
        $this->{'initexpr'}->getType($ck);
    }

    $ck->pushLocalBlock($this->{'stmts'});

    $this->{'iterexpr'}->getType($ck);

    my $condtype = $this->{'condexpr'}->getType($ck);
    S2::error($this, "Non-boolean for loop conditional") unless $condtype->isBoolable();


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

    $o->tabwrite("for (");
    $this->{'vardecl'}->asPerl($bp, $o, { as_expr => 1 }) if $this->{'vardecl'};
    $this->{'initexpr'}->asPerl($bp, $o) if $this->{'initexpr'};

    $o->write("; ");

    $this->{'condexpr'}->asPerl($bp, $o);

    $o->write("; ");

    $this->{'iterexpr'}->asPerl($bp, $o);
    
    $o->write(") ");

    $this->{'stmts'}->asPerl($bp, $o);
    $o->newline();
}

