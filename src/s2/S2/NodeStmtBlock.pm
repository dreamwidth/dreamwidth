#!/usr/bin/perl
#

package S2::NodeStmtBlock;

use strict;
use S2::Node;
use S2::NodeStmt;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $node = new S2::Node;
    $node->{'stmtlist'} = [];
    $node->{'returnType'} = undef;
    $node->{'localvars'} = {}; # string -> Type
    $node->{'localvarundecorated'} = {}; # string -> something defined
    bless $node, $class;
}

sub parse {
    my ($class, $toker, $isDecl) = @_;
    my $ns = new S2::NodeStmtBlock;
    $ns->setStart($ns->requireToken($toker, $S2::TokenPunct::LBRACE));

    my $loop = 1;
    my $closed = 0;

    do {
        $ns->skipWhite($toker);
        my $p = $toker->peek();

        if (! defined $p) {
            $loop = 0;
        } elsif ($p == $S2::TokenPunct::RBRACE) {
            $ns->eatToken($toker);
            $closed = 1;
            $loop = 0;
        } elsif (S2::NodeStmt->canStart($toker)) {
            my $s = parse S2::NodeStmt $toker;
            push @{$ns->{'stmtlist'}}, $s;
            $ns->addNode($s);
        } else {
            S2::error($p, "Unexpected token parsing statement block");
        }

    } while ($loop);

    S2::error($ns, "Didn't find closing brace in statement block")
        unless $closed;

    return $ns;
}

sub addLocalVar {
    my ($this, $v, $t, $undecorated) = @_;
    $this->{'localvars'}->{$v} = $t;
    $this->{'localvarundecorated'}->{$v} = 1 if $undecorated;
}

sub getLocalVar {
    my ($this, $v) = @_;
    $this->{'localvars'}->{$v};
}

sub localVarMustBeDecorated {
    my ($this, $v) = @_;
    return ! defined($this->{'localvarundecorated'}->{$v});
}

sub setReturnType {
    my ($this, $t) = @_;
    $this->{'returnType'} = $t;
}

sub willReturn {
    my ($this) = @_;

    return 0 unless @{$this->{'stmtlist'}};
    my $ns = $this->{'stmtlist'}->[-1];

    # a return statement obviously returns
    return 1 if $ns->isa('S2::NodeReturnStmt');

    # and if statement at the end of a function returns
    # if all paths return, so ask the ifstatement
    if ($ns->isa('S2::NodeIfStmt')) {
        return $ns->willReturn();
    }

    # all other types don't return
    return 0;
}

sub check {
    my ($this, $l, $ck) = @_;
    
    # set the return type for any returnstmts that need it.
    # NOTE: the returnType is non-null if and only if it's
    # attached to a function.
    $ck->setReturnType($this->{'returnType'}) 
        if $this->{'returnType'};
    
    foreach my $ns (@{$this->{'stmtlist'}}) {
        $ns->check($l, $ck);
    }

    if ($this->{'returnType'} && 
        ! $this->{'returnType'}->equals($S2::Type::VOID) &&
        ! $this->willReturn()) {
        S2::error($this, "Statement block isn't guaranteed to return (should return " .
                  $this->{'returnType'}->toString . ")");
    }
}

sub asS2 {
    my ($this, $o) = @_;
    $o->writeln("{");
    $o->tabIn();
    foreach my $ns (@{$this->{'stmtlist'}}) {
        $ns->asS2($o);
    }
    $o->tabOut();
    $o->tabwrite("}");
}

sub asPerl {
    my ($this, $bp, $o, $doCurlies) = @_;
    $doCurlies = 1 unless defined $doCurlies;

    if ($doCurlies) {
        $o->writeln("{");
        $o->tabIn();
    }

    foreach my $ns (@{$this->{'stmtlist'}}) {
        $ns->asPerl($bp, $o);
    }

    if ($doCurlies) {
        $o->tabOut();
        $o->tabwrite("}");
    }
}


