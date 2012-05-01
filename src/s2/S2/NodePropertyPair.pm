#!/usr/bin/perl
#

package S2::NodePropertyPair;

use strict;
use S2::Node;
use S2::NodeText;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $node = new S2::Node;
    bless $node, $class;
}

sub canStart {
    my ($class, $toker) = @_;
    return S2::NodeText->canStart($toker);
}

sub getKey { shift->{'key'}->getText(); }
sub getVal { shift->{'val'}->getText(); }

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodePropertyPair;
    $n->addNode($n->{'key'} = S2::NodeText->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::ASSIGN);
    $n->addNode($n->{'val'} = S2::NodeText->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::SCOLON);
    return $n;
}

sub asS2 {
    my ($this, $o) = @_;
    $o->tabwrite("");
    $this->{'key'}->asS2($o);
    $o->write(" = ");
    $this->{'val'}->asS2($o);
    $o->write(";");
}
