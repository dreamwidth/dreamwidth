#!/usr/bin/perl
#

package S2::NodeArrayLiteral;

use strict;
use S2::Node;
use S2::NodeExpr;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $node = new S2::Node;
    $node->{'keys'} = [];
    $node->{'vals'} = [];
    bless $node, $class;
}

sub canStart {
    my ($class, $toker) = @_;
    return $toker->peek() == $S2::TokenPunct::LBRACK ||
        $toker->peek() == $S2::TokenPunct::LBRACE;
}

# [ <NodeExpr>? (, <NodeExpr>)* ,? ]
# { (<NodeExpr> => <NodeExpr> ,)* }

sub parse {
    my ($this, $toker) = @_;

    my $nal = new S2::NodeArrayLiteral;

    my $t = $toker->peek();	
    if ($t == $S2::TokenPunct::LBRACK) {
        $nal->{'isArray'} = 1;
        $nal->setStart($nal->requireToken($toker, $S2::TokenPunct::LBRACK));
    } else {
        $nal->{'isHash'} = 1;
        $nal->setStart($nal->requireToken($toker, $S2::TokenPunct::LBRACE));
    }
        
    my $need_comma = 0;
    while (1) {
        $t = $toker->peek();

        # find the ends
        if ($nal->{'isArray'} && $t == $S2::TokenPunct::RBRACK) {
            $nal->requireToken($toker, $S2::TokenPunct::RBRACK);
            return $nal;
        }
        if ($nal->{'isHash'} && $t == $S2::TokenPunct::RBRACE) {
            $nal->requireToken($toker, $S2::TokenPunct::RBRACE);
            return $nal;
        }

        S2::error($t, "Expecting comma") if $need_comma;

        if ($nal->{'isArray'}) {
            my $ne = S2::NodeExpr->parse($toker);
            push @{$nal->{'vals'}}, $ne;
            $nal->addNode($ne);
        } elsif ($nal->{'isHash'}) {
            my $ne = S2::NodeExpr->parse($toker);
            push @{$nal->{'keys'}}, $ne;
            $nal->addNode($ne);

            $nal->requireToken($toker, $S2::TokenPunct::HASSOC);

            $ne = S2::NodeExpr->parse($toker);
            push @{$nal->{'vals'}}, $ne;
            $nal->addNode($ne);
        }

        $need_comma = 1;
        if ($toker->peek() == $S2::TokenPunct::COMMA) {
            $nal->requireToken($toker, $S2::TokenPunct::COMMA);
            $need_comma = 0;
        }
    }
    
    
}

sub getType {
    my ($this, $ck, $wanted) = @_;

    # in case of empty array [] or hash {}, the type is what they wanted,
    # if they wanted an array/hash, otherwise void[] or void{}
    my $t;
    my $vals = scalar @{$this->{'vals'}};
    unless ($vals) {
        if ($wanted) {
            if (($this->{isArray} && $wanted->isArrayOf()) || ($this->{isHash} && $wanted->isHashOf())) {
                return $wanted;
            }
        }
        $t = new S2::Type("void");
        $t->makeArrayOf() if $this->{'isArray'};
        $t->makeHashOf() if $this->{'isHash'};
        return $t;
    }

    $t = $this->{'vals'}->[0]->getType($ck)->clone();
    for (my $i=1; $i<$vals; $i++) {
        my $next = $this->{'vals'}->[$i]->getType($ck);
        next if $t->equals($next);
        S2::error($this, "Hash/array literal with inconsistent types: ".
                  "starts with ". $t->toString .", but then has ".
                  $next->toString);
    }
    
    if ($this->{'isHash'}) {
        for (my $i=0; $i<$vals; $i++) {
            my $t = $this->{'keys'}->[$i]->getType($ck);
            next if $t->equals($S2::Type::STRING) ||
                $t->equals($S2::Type::INT);
            S2::error($this, "Hash keys must be strings or ints.");
        }        
    }

    $t->makeArrayOf() if $this->{'isArray'};
    $t->makeHashOf() if $this->{'isHash'};
    return $t;
}    

sub asS2 {
    my ($this, $o) = @_;
    die "Not ported.";
}

sub asPerl {
    my ($this, $bp, $o) = @_;

    $o->writeln($this->{'isArray'} ? "[" : "{");
    $o->tabIn();

    my $size = scalar @{$this->{'vals'}};
    for (my $i=0; $i<$size; $i++) {
        $o->tabwrite("");
        if ($this->{'isHash'}) {
            $this->{'keys'}->[$i]->asPerl($bp, $o);
            $o->write(" => ");
        }
        $this->{'vals'}->[$i]->asPerl($bp, $o);
        $o->writeln(",");
    }
    $o->tabOut();
    $o->tabwrite($this->{'isArray'} ? "]" : "}");
}

__END__

    public void asS2 (Indenter o)
    {
	o.writeln(isArray ? "[" : "{");
        o.tabIn();
        ListIterator liv = vals.listIterator();
        ListIterator lik = keys.listIterator();
        Node n;
        while (liv.hasNext()) {
            o.tabwrite("");
            if (isHash) {
                n = (Node) lik.next();
                n.asS2(o);
                o.write(" => ");
            }
            n = (Node) liv.next();
            n.asS2(o);
            o.writeln(",");
        }
        o.tabOut();
	o.tabwrite(isArray ? "]" : "}");
    }

