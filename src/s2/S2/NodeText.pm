#!/usr/bin/perl
#

package S2::NodeText;

use strict;
use S2::Node;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $node = new S2::Node;
    bless $node, $class;
}

sub parse {
    my ($class, $toker) = @_;
    my $nt = new S2::NodeText;

    $nt->skipWhite($toker);
    my $t = $toker->peek();

    if ($t->isa('S2::TokenIdent')) {
        my $ti = $toker->getToken();
        $nt->addToken($ti);
        $nt->{'text'} = $ti->getIdent();
        $ti->setType($S2::TokenIdent::STRING);
    } elsif ($t->isa('S2::TokenIntegerLiteral')) {
        $nt->addToken($toker->getToken());
        $nt->{'text'} = $t->getInteger();
    } elsif ($t->isa('S2::TokenStringLiteral')) {
        $nt->addToken($toker->getToken());
        $nt->{'text'} = $t->getString();
    } else {
        S2::error($t, "Expecting text (integer, string, or identifer)");
    }

    return $nt;
}

sub canStart {
    my ($class, $toker) = @_;
    my $t = $toker->peek();
    return $t->isa("S2::TokenIdent") ||
        $t->isa("S2::TokenIntegerLiteral") ||
        $t->isa("S2::TokenStringLiteral");
}

sub getText { shift->{'text'}; }

sub asS2 {
    my ($this, $o) = @_;
    $o->write(S2::Backend::quoteString($this->{'text'}));
}


