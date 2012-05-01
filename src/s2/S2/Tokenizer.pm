#!/usr/bin/perl
#

use strict;
use S2::FilePos;
use S2::TokenPunct;
use S2::TokenWhitespace;
use S2::TokenIdent;
use S2::TokenIntegerLiteral;
use S2::TokenPunct;
use S2::TokenComment;
use S2::TokenStringLiteral;

package S2::Tokenizer;

sub new # (fh) class method
{
    my ($class, $content) = @_;

    my $this = {};
    bless $this, $class;
    
    if (ref $content eq "SCALAR") {
        $this->{'content'} = $content;
        $this->{'length'} = length $$content;
    }
    $this->{'pos'} = 0;
    $this->{'line'} = 1;
    $this->{'col'} = 1;
    $this->{'inString'} = 0;  # (accessed directly elsewhere)
    $this->{'inStringStack'} = [];
    $this->{'peekedToken'} = undef;
    return $this;
}

sub pushInString {
    my ($this, $val) = @_;
    push @{$this->{'inStringStack'}}, $this->{'inString'};
    $this->{'inString'} = $val;
    #print STDERR "PUSH: $val Stack: @{$this->{'inStringStack'}}\n";
}

sub popInString {
    my ($this) = @_;
    my $was = $this->{'inString'};
    $this->{'inString'} = pop @{$this->{'inStringStack'}};
    #print STDERR "POP: $this->{'inString'} Stack: @{$this->{'inStringStack'}}\n";
    if ($was != $this->{'inString'} && $this->{'peekedToken'}) {
        # back tokenizer up and discard our peeked token
        pos(${$this->{'content'}}) = $this->{'peekedToken'}->{'pos_re'};
        $this->{'peekedToken'} = undef;
    }
}

sub peek # () method : Token
{
    $_[0]->{'peekedToken'} ||= $_[0]->getToken(1);
}

sub getToken # () method : Token
{
    my ($this, $just_peek) = @_;

    # return peeked token if we have one
    if (my $t = $this->{'peekedToken'}) {
        $this->{'peekedToken'} = undef;
        $this->moveLineCol($t) unless $just_peek;
        return $t;
    }

    my $pos = $this->getPos();
    my $pos_re = pos(${$this->{'content'}});
    my $nxtoken = $this->makeToken();
    if ($nxtoken) {
        $nxtoken->{'pos'} = $pos;
        $nxtoken->{'pos_re'} = $pos_re;
        $this->moveLineCol($nxtoken) unless $just_peek;
    }
#    print STDERR "Token: ", $nxtoken->toString, "\n";
    return $nxtoken;
}

sub getPos # () method : FilePos
{
    return new S2::FilePos($_[0]->{'line'},
                           $_[0]->{'col'});
}

sub moveLineCol {
    my ($this, $t) = @_;
    if (my $newlines = ($t->{'chars'} =~ tr/\n/\n/)) {
#        print STDERR "Chars: $t [$t->{'chars'}] Lines: $newlines\n";
        $this->{'line'} += $newlines;
        $t->{'chars'} =~ /\n(.+)$/m;
        my $match = defined $1 ? $1 : '';
        $this->{col} = 1 + length $match;
    } else {
#        print STDERR "Chars: $t [$t->{'chars'}]\n";
        $this->{'col'} += length $t->{'chars'};
    }
}

sub makeToken # () method private : Token
{
    my $this = shift;
    my $c = $this->{'content'};

    # finishing or trying to finish an open quoted string
    if ($this->{'inString'} == 1 &&
        $$c =~ /\G((\\[\\\"\$]|[^\"\$])*)(\")?/sgc) {
        my $source = $1;
        my $closed = $3 ? 1 : 0;
        return S2::TokenStringLiteral->new(undef, $source, 0, $closed);
    }

    # finishing a triple quoted string
    if ($this->{'inString'} == 3) {
        if ($$c =~ /\G((\\[\\\"\$]|[^\$])*?)\"\"\"/sgc) {
            my $source = $1;
            return S2::TokenStringLiteral->new(undef, $source, 0, 3);
        }

        # not finishing a triple quoted string (end in $)
        if ($$c =~ /\G((\\[\\\"\$]|[^\$])*)/sgc) {
            my $source = $1;
            return S2::TokenStringLiteral->new(undef, $source, 0, 0);
        }
    }

    # not in a string, but one's starting
    if ($this->{'inString'} == 0 && $$c =~ /\G\"/gc) {
        # triple start and triple end
        if ($$c =~ /\G\"\"((\\[\\\"\$]|[^\$])*?)\"\"\"/gc) {
            my $source = $1;
            return S2::TokenStringLiteral->new(undef, $source, 3, 3);
        }
        
        # triple start and variable end
        if ($$c =~ /\G\"\"((\\[\\\"\$]|[^\$])*)/gc) {
            my $source = $1;
            return S2::TokenStringLiteral->new(undef, $source, 3, 0);
        }
        
        # single start and maybe end
        if ($$c =~ /\G((\\[\\\"\$]|[^\"\$])*)(\")?/gc) {
            my $source = $1;
            my $closed = $3 ? 1 : 0;
            return S2::TokenStringLiteral->new(undef, $source, 1, $closed);
        }
    }

    if ( $$c =~ /\G(\s+)/gc ) {
        my $ws = $1;
        return S2::TokenWhitespace->new($ws);
    }

    if ($$c =~ /\G(<=?|>=?|==|=>?|!=|\+\+?|->|--?|;|::?|&&?|\|\|?|\*|\/|%|!|\.\.?|\{|\}|\[|\]|\(|\)|,|\?|\$)/gc) {
        return S2::TokenPunct->new($1);
    }

    if ( $$c =~ /\G([a-zA-Z\_]\w*)/gc ) {
        my $ident = $1;
        return S2::TokenIdent->new($ident);
    }

    if ($$c =~ /\G(\d+)/gc) {
        my $iv = $1;
        return S2::TokenIntegerLiteral->new($iv);
    }
    
    if ( $$c =~ /\G(\#.*\n?)/gc ) {
        return S2::TokenComment->new( $1 );
    }

    if ( $$c =~ /(.+)/gc ) {
        S2::error( $this->getPos(), "Parse error!  Unknown token.  ($1)" );
    }
    
    return undef;
}

sub peekChar {
    my $this = shift;
    my $pos = pos(${$this->{'content'}});
    my $ch = substr(${$this->{'content'}}, $pos, 1);
    #print STDERR "pos = $pos, char = $ch\n";
    return $ch;
}

1;
