#!/usr/bin/perl
#

package S2::NodeNamedType;

use strict;
use S2::Node;
use S2::NodeType;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class, $name, $type) = @_;
    my $node = new S2::Node;
    $node->{'name'} = $name;
    $node->{'type'} = $type;
    bless $node, $class;
}

sub cleanForFreeze {
    my $this = shift;
    delete $this->{'tokenlist'};
    $this->{'typenode'}->cleanForFreeze();
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeNamedType;

    $n->{'typenode'} = S2::NodeType->parse($toker);
    $n->{'type'} = $n->{'typenode'}->getType();

    $n->addNode($n->{'typenode'});
    $n->{'name'} = $n->getIdent($toker)->getIdent();

    return $n;
}

sub getType { shift->{'type'}; }
sub getName { shift->{'name'}; }

sub asS2 {
    my ($this, $o) = @_;
    $this->{'typenode'}->asS2($o);
}

sub toString {
    my ($this, $l, $ck) = @_;
    $this->{'type'}->toString() . " $this->{'name'}";
}

