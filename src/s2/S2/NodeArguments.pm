#!/usr/bin/perl
#

package S2::NodeArguments;

use strict;
use S2::Node;
use S2::NodeExpr;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $node = new S2::Node;
    $node->{'args'} = [];
    bless $node, $class;
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeArguments;

    $n->setStart($n->requireToken($toker, $S2::TokenPunct::LPAREN));
    while (1) {
        my $tp = $toker->peek();
        if ($tp == $S2::TokenPunct::RPAREN) {
            $n->eatToken($toker);
            return $n;
        }

        my $expr = parse S2::NodeExpr $toker;
        push @{$n->{'args'}}, $expr;
        $n->addNode($expr);
        if ($toker->peek() == $S2::TokenPunct::COMMA) {
            $n->eatToken($toker);
        }
    }
}

sub asS2 {
    my ($this, $o) = @_;
    die "not ported";
}

sub asPerl {
    my ($this, $bp, $o, $doCurlies) = @_;
    $doCurlies = 1 unless defined $doCurlies;
    $o->write("(") if $doCurlies;
    my $didFirst = 0;
    foreach my $n (@{$this->{'args'}}) {
        $o->write(", ") if $didFirst++;
        $n->asPerl($bp, $o);
    }
    $o->write(")") if $doCurlies;
}

sub typeList {
    my ($this, $ck) = @_;
    return join(',', map { $_->getType($ck)->toString() }
                @{$this->{'args'}});
}
