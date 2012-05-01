#!/usr/bin/perl
#

package S2::Node;

use strict;

sub new {
    my ($class) = @_;
    my $node = {
        'startPos' => undef,
        'tokenlist' => [],
    };
    bless $node, $class;
}

sub cleanForFreeze {
    my $this = shift;
    delete $this->{'tokenlist'};
    delete $this->{'_cache_type'};
}

sub setStart {
    my ($this, $arg) = @_;

    if ($arg->isa('S2::Token') || $arg->isa('S2::Node')) {
        $this->{'startPos'} =
            $arg->getFilePos()->clone();
    } elsif ($arg->isa('S2::FilePos')) {
        $this->{'startPos'} =
            $arg->clone();
    } else {
        die "Unexpected argument.\n";
    }
}

sub check {
    my ($this, $l, $ck) = @_;
    die "FIXME: check not implemented for $this\n";
}

sub asHTML {
    my ($this, $o) = @_;
    foreach my $el (@{$this->{'tokenlist'}}) {
        # $el is an S2::Token or S2::Node
        $el->asHTML($o);
    }
}

sub asS2 {
    my ($this, $o) = @_;
    $o->tabwriteln("###$this:::asS2###");
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    $o->tabwriteln("###${this}::asPerl###");
}

sub asPerl_bool {
    my ($this, $bp, $o) = @_;
    my $ck = $S2::CUR_COMPILER->{'checker'};
    my $s2type = $this->getType($ck);

    # already boolean
    if ($s2type->equals($S2::Type::BOOL) || $s2type->equals($S2::Type::INT)) {
        $this->asPerl($bp, $o);
        return;
    }
    
    # S2 semantics and perl semantics differ ("0" is true in S2)
    if ($s2type->equals($S2::Type::STRING)) {
        $o->write("((");
        $this->asPerl($bp, $o);
        $o->write(") ne '')");
        return;
    }

    # is the object defined?
    if ($s2type->isSimple()) {
        $o->write("S2::check_defined(");
        $this->asPerl($bp, $o);
        $o->write(")");
        return;
    }

    # does the array have elements?
    if ($s2type->isArrayOf() || $s2type->isHashOf()) {
        if ($bp->oo) {
            $o->write("S2::Runtime::OO::_check_elements(");
        }
        else {
            $o->write("S2::check_elements(");
        }
        $this->asPerl($bp, $o);
        $o->write(")");
        return;
    }

    S2::error($this, "Unhandled internal case for NodeTerm::asPerl_bool()");
}

sub setTokenList {
    my ($this, $newlist) = @_;
    $this->{'tokenlist'} = $newlist;
}

sub getTokenList {
    my ($this) = @_;
    $this->{'tokenlist'};
}

sub addNode {
    my ($this, $subnode) = @_;
    push @{$this->{'tokenlist'}}, $subnode;
}

sub addToken {
    my ($this, $t) = @_;
    push @{$this->{'tokenlist'}}, $t;
}

sub eatToken {
    my ($this, $toker, $ignoreSpace) = @_;
    $ignoreSpace = 1 unless defined $ignoreSpace;
    my $t = $toker->getToken();
    $this->addToken($t);
    if ($ignoreSpace) {
        $this->skipWhite($toker);
    }
    return $t;
}

sub requireToken {
    my ($this, $toker, $t, $ignoreSpace) = @_;
    $ignoreSpace = 1 unless defined $ignoreSpace;
    if ($ignoreSpace) { $this->skipWhite($toker); }
    
    my $next = $toker->getToken();
    S2::error($next, "Unexpected end of file found") unless $next;

    unless ($next == $t) {
        S2::error(undef, "internal error") unless $t;
        S2::error($next, "Unexpected token found.  ".
                  "Expecting: " . $t->toString() . "\nGot: " . $next->toString());
    }
    $this->addToken($next);
    if ($ignoreSpace) { $this->skipWhite($toker); }
    return $next;
}

sub getStringLiteral {
    my ($this, $toker, $ignoreSpace) = @_;
    $ignoreSpace = 1 unless defined $ignoreSpace;
    if ($ignoreSpace) { $this->skipWhite($toker); }

    my $t = $toker->getToken();
    S2::error($t, "Expected string literal")
        unless $t && $t->isa("S2::TokenStringLiteral");
    
    $this->addToken($t);
    return $t;
}

sub getIdent {
    my ($this, $toker, $addToList, $ignoreSpace) = @_;
    $addToList = 1 unless defined $addToList;
    $ignoreSpace = 1 unless defined $ignoreSpace;
    
    my $id = $toker->peek();
    unless ($id->isa("S2::TokenIdent")) {
        S2::error($id, "Expected identifier.");
    }
    if ($addToList) {
        $this->eatToken($toker, $ignoreSpace);
    }
    return $id;
}

sub skipWhite {
    my ($this, $toker) = @_;
    while (my $next = $toker->peek()) {
        return if $next->isNecessary();
        $this->addToken($toker->getToken());
    }
}

sub getFilePos {
    my ($this) = @_;

    # most nodes should set their position
    return $this->{'startPos'} if $this->{'startPos'};

    # if the node didn't record its position, try to figure it out
    # from where the first token is at
    my $el = $this->{'tokenlist'}->[0];
    return $el->getFilePos() if $el;
    return undef;
}

sub getType {
    my ($this, $ck, $wanted) = @_;
    die "FIXME: getType(ck) not implemented in $this\n";
}

# kinda a crappy part to put this, perhaps.  but all expr
# nodes don't inherit from NodeExpr.  maybe they should?
sub isLValue {
    my ($this) = @_;
    # hack:  only NodeTerms inside NodeExprs can be true
    if ($this->isa('S2::NodeExpr')) {
        my $n = $this->getExpr();
        if ($n->isa('S2::NodeTerm')) {
            return $n->isLValue();
        }
    }
    return 0;
}

sub makeAsString {
    my ($this, $ck) = @_;
    return 0;
}

sub isProperty {
    0;
}

1;
