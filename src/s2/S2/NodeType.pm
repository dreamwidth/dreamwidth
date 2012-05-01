#!/usr/bin/perl
#

package S2::NodeType;

use strict;
use S2::Node;
use S2::Type;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class, $name, $type) = @_;
    my $node = new S2::Node;
    $node->{'type'} = undef;
    bless $node, $class;
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeType;
    
    my $base = $n->getIdent($toker, 1, 0);
    $base->setType($S2::TokenIdent::TYPE);

    if ($base->getIdent() eq "null") {
        S2::error($n, "Cannot declare items of type 'null'");
    }

    $n->{'type'} = S2::Type->new($base->getIdent());
    while ($toker->peek() == $S2::TokenPunct::LBRACK ||
           $toker->peek() == $S2::TokenPunct::LBRACE) {
        my $t = $toker->peek();
        $n->eatToken($toker, 0);
        
        if ($t == $S2::TokenPunct::LBRACK) {
            $n->requireToken($toker, $S2::TokenPunct::RBRACK, 0);
            $n->{'type'}->makeArrayOf();
        } elsif ($t == $S2::TokenPunct::LBRACE) {
            $n->requireToken($toker, $S2::TokenPunct::RBRACE, 0);
            $n->{'type'}->makeHashOf();
        }
    }

    # If the type was a simple type, we have to remove whitespace,
    # since we explictly said not to above.
    $n->skipWhite($toker);
    return $n;
}

sub getType { shift->{'type'}; }

sub asS2 {
    my ($this, $o) = @_;
    $o->write($this->{'type'}->toString());
}


