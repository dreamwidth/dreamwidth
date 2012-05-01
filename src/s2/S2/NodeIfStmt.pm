#!/usr/bin/perl
#

package S2::NodeIfStmt;

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
    return $toker->peek() == $S2::TokenKeyword::IF;
}

sub parse {
    my ($class, $toker) = @_;

    my $n = new S2::NodeIfStmt;
    $n->{'elseifblocks'} = [];
    $n->{'elseifexprs'} = [];

    $n->setStart($n->requireToken($toker, $S2::TokenKeyword::IF));
    $n->requireToken($toker, $S2::TokenPunct::LPAREN);
    $n->addNode($n->{'expr'} = S2::NodeExpr->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::RPAREN);
    $n->addNode($n->{'thenblock'} = S2::NodeStmtBlock->parse($toker));
    
    while ($toker->peek() == $S2::TokenKeyword::ELSEIF) {
        $n->eatToken($toker);
        $n->requireToken($toker, $S2::TokenPunct::LPAREN);
        my $expr = S2::NodeExpr->parse($toker);
        $n->addNode($expr);
        $n->requireToken($toker, $S2::TokenPunct::RPAREN);
        push @{$n->{'elseifexprs'}}, $expr;

        my $nie = S2::NodeStmtBlock->parse($toker);
        $n->addNode($nie);
        push @{$n->{'elseifblocks'}}, $nie;
    }

    if ($toker->peek() == $S2::TokenKeyword::ELSE) {
        $n->eatToken($toker);
        $n->addNode($n->{'elseblock'} =
                    S2::NodeStmtBlock->parse($toker));
    }

    return $n;
}

# returns true if and only if the 'then' stmtblock ends in a
# return statement, the 'else' stmtblock is non-null and ends
# in a return statement, and any elseif stmtblocks end in a return
# statement.
sub willReturn {
    my ($this) = @_;
    return 0 unless $this->{'elseblock'};
    return 0 unless $this->{'thenblock'}->willReturn();
    return 0 unless $this->{'elseblock'}->willReturn();
    foreach (@{$this->{'elseifblocks'}}) {
        return 0 unless $_->willReturn();
    }
    return 1;
}

sub check {
    my ($this, $l, $ck) = @_;

    my $expr = $this->{'expr'};

    my $t = $expr->getType($ck);
    S2::error($this, "Non-boolean if test") unless $t->isBoolable();

    my $check_assign = sub {
	my $ex = shift;
	my $innerexpr = $ex->getExpr;
	if ($innerexpr->isa("S2::NodeAssignExpr")) {
	    S2::error($ex, "Assignments not allowed bare in conditionals.  Did you mean to use == instead?  If not, wrap assignment in parens.");
	  }
    };
    $check_assign->($expr);

    $ck->pushLocalBlock($this->{'thenblock'});
    $this->{'thenblock'}->check($l, $ck);
    $ck->popLocalBlock();

    foreach my $ne (@{$this->{'elseifexprs'}}) {
        $t = $ne->getType($ck);
        S2::error($ne, "Non-boolean if test") unless $t->isBoolable();
	$check_assign->($ne);
    }

    foreach my $sb (@{$this->{'elseifblocks'}}) {
        $ck->pushLocalBlock($sb);
        $sb->check($l, $ck);
        $ck->popLocalBlock();
    }

    if ($this->{'elseblock'}) {
        $ck->pushLocalBlock($this->{'elseblock'});
        $this->{'elseblock'}->check($l, $ck);
        $ck->popLocalBlock();
    }
}

sub asS2 {
    my ($this, $o) = @_;
    die "Unported";
}

sub asPerl {
    my ($this, $bp, $o) = @_;

    # if
    $o->tabwrite("if (");
    $this->{'expr'}->asPerl_bool($bp, $o);
    $o->write(") ");
    $this->{'thenblock'}->asPerl($bp, $o);
	
    # else-if
    my $i = 0;
    foreach my $expr (@{$this->{'elseifexprs'}}) {
        my $block = $this->{'elseifblocks'}->[$i++];
        $o->write(" elsif (");
        $expr->asPerl_bool($bp, $o);
        $o->write(") ");
        $block->asPerl($bp, $o);
    }

    # else
    if ($this->{'elseblock'}) {
        $o->write(" else ");
        $this->{'elseblock'}->asPerl($bp, $o);
    }
    $o->newline();
}
