#!/usr/bin/perl
#

package S2::NodeBranchStmt;

use strict;
use S2::Node;
use S2::NodeExpr;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub canStart {
    my ($class, $toker) = @_;
    return $toker->peek() == $S2::TokenKeyword::BREAK
        || $toker->peek() == $S2::TokenKeyword::CONTINUE;
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeBranchStmt;
    
    my $kw = $toker->getToken();
    $n->setStart($kw);
    $n->addToken($kw);

    if ($kw == $S2::TokenKeyword::BREAK || $kw == $S2::TokenKeyword::CONTINUE) {
        $n->{type} = $kw;
    }
    else {
        S2::error($n, "A branch statement cannot start with ".$n->toString);
    }

    $n->requireToken($toker, $S2::TokenPunct::SCOLON);
    return $n;
}

sub check {
    my ($this, $l, $ck) = @_;

    S2::error($this, "Can't ".$this->{type}->getIdent()." here") unless $ck->inBreakable();
}

sub asS2 {
    my ($this, $o) = @_;
    $o->tabwrite($this->{type}->getIdent());
    $o->writeln(";");
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    
    if ($this->{type} == $S2::TokenKeyword::BREAK) {
        $o->tabwriteln("last;");
    }
    else {
        $o->tabwriteln("next;");
    }
}

