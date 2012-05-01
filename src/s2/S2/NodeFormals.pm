#!/usr/bin/perl
#

package S2::NodeFormals;

use strict;
use S2::Node;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class, $formals) = @_;
    my $node = new S2::Node;
    $node->{'listFormals'} = $formals || [];
    bless $node, $class;
}

sub cleanForFreeze {
    my $this = shift;
    delete $this->{'tokenlist'};
    foreach (@{$this->{'listFormals'}}) { $_->cleanForFreeze; }
}

sub parse {
    my ($class, $toker, $isDecl) = @_;
    my $n = new S2::NodeFormals;
    my $count = 0;

    $n->requireToken($toker, $S2::TokenPunct::LPAREN);
    while ($toker->peek() != $S2::TokenPunct::RPAREN) {
        $n->requireToken($toker, $S2::TokenPunct::COMMA) if $count;
        $n->skipWhite($toker);

        my $nf = parse S2::NodeNamedType $toker;
        push @{$n->{'listFormals'}}, $nf;
        $n->addNode($nf);

        $n->skipWhite($toker);
        $count++;
    }
    $n->requireToken($toker, $S2::TokenPunct::RPAREN);
    return $n;
}

sub check {
    my ($this, $l, $ck) = @_;
    my %seen;
    foreach my $nt (@{$this->{'listFormals'}}) {
        my $name = $nt->getName();
        S2::error($nt, "Duplicate argument named $name") if $seen{$name}++;
        my $t = $nt->getType();
        unless ($ck->isValidType($t)) {
            S2::error($nt, "Unknown type " . $t->toString);
        }
    }
}

sub asS2 {
    my ($this, $o) = @_;
    return unless @{$this->{'listFormals'}};
    $o->write($this->toString());
}

sub toString {
    my ($this) = @_;
    return "(" . join(", ", map { $_->toString } 
                      @{$this->{'listFormals'}}) . ")";
}

sub getFormals { shift->{'listFormals'}; }

# static
sub variations {
    my ($nf, $ck) = @_;  # NodeFormals, Checker
    my $l = [];
    if ($nf) {
        $nf->getVariations($ck, $l, [], 0);
    } else {
        push @$l, new S2::NodeFormals;
    }
    return $l;
}

sub getVariations {
    my ($this, $ck, $vars, $temp, $col) = @_;
    my $size = @{$this->{'listFormals'}};

    if ($col == $size) {
        push @$vars, new S2::NodeFormals($temp);
        return;
    }
    
    my $nt = $this->{'listFormals'}->[$col]; # NodeNamedType
    my $t = $nt->getType();

    foreach my $st (@{$t->subTypes($ck)}) {
        my $newtemp = [ @$temp ];  # hacky clone (not cloning member objects)
        push @$newtemp, new S2::NodeNamedType($nt->getName(), $st);
        $this->getVariations($ck, $vars, $newtemp, $col+1);
    }
}

sub typeList {
    my $this = shift;
    return join(',', map { $_->getType()->toString } 
                @{$this->{'listFormals'}});

    # debugging implementation:
    #my @list;
    #foreach my $nnt (@{$this->{'listFormals'}}) { # NodeNamedType
    #    my $t = $nnt->getType();
    #    if (ref $t ne "S2::Type") {
    #        print STDERR "Is: $t\n";
    #        S2::error() 
    #    }
    #    push @list, $t->toString;
    #}
    #return join(',', @list);
}


# adds all these variables to the stmtblock's symbol table
sub populateScope {
    my ($this, $nb) = @_;  # NodeStmtBlock
    foreach my $nt (@{$this->{'listFormals'}}) {
	$nb->addLocalVar($nt->getName(), $nt->getType());
     }
}





