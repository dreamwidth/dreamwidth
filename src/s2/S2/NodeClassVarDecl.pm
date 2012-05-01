#!/usr/bin/perl
#

package S2::NodeClassVarDecl;

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
    delete $this->{'docstring'};
    $this->{'typenode'}->cleanForFreeze;
}

sub getType { shift->{'type'}; }
sub getName { shift->{'name'}; }
sub getDocString { shift->{'docstring'}; }
sub isReadOnly { shift->{'readonly'}; }

sub parse {
    my ($class, $toker) = @_;

    my $n = new S2::NodeClassVarDecl;

    # get the function keyword
    $n->setStart($n->requireToken($toker, $S2::TokenKeyword::VAR));

    if ($toker->peek() == $S2::TokenKeyword::READONLY) {
        $n->{'readonly'} = 1;
        $n->eatToken($toker);
    }

    $n->{'typenode'} = parse S2::NodeType $toker;
    $n->{'type'} = $n->{'typenode'}->getType();
    $n->addNode($n->{'typenode'});

    $n->{'name'} = $n->getIdent($toker)->getIdent();

    # docstring
    if ($toker->peek()->isa('S2::TokenStringLiteral')) {
        my $t = $n->eatToken($toker);
        $n->{'docstring'} = $t->getString();
    }

    $n->requireToken($toker, $S2::TokenPunct::SCOLON);
    return $n;
}

sub asS2 {
    my ($this, $o) = @_;
    die "not done";
}

sub asString {
    my $this = shift;
    return join(' ', $this->{'type'}->toString, $this->{'name'});
}

__END__


