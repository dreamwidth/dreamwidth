#!/usr/bin/perl
#

package S2::TokenStringLiteral;

use strict;
use S2::Token;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Token);

#    int quotesLeft;
#    int quotesRight;
#    String text;
#    String source;

sub new
{
    my $class = shift;
    my ($text, $source, $ql, $qr);
    if (@_ == 1) {
        $text = shift;
        ($ql, $qr) = (1, 1);
        $source = $text;
    } elsif (@_ == 3) {
        ($text, $ql, $qr) = @_;
        $source = $text;
    } elsif (@_ == 4) {
        ($text, $source, $ql, $qr) = @_;
        unless (defined $text) {
            $text = $source;
            $text =~ s/\\n/\n/g;
            $text =~ s/\\\"/\"/g;
            $text =~ s/\\\$/\$/g;
            $text =~ s/\\\\/\\/g;
        }
    } else {
        die;
    }
    
    bless {
        'text' => $text,
        'chars' => $source,
        'quotesLeft' => $ql,
        'quotesRight' => $qr,
    }, $class;
}

sub getQuotesLeft { shift->{'quotesLeft'}; }
sub getQuotesRight { shift->{'quotesRight'}; }
sub setQuotesLeft { my $this = shift; $this->{'quotesLeft'} = shift; }
sub setQuotesRight { my $this = shift; $this->{'quotesRight'} = shift; }

sub clone {
    my $this = shift;
    return S2::TokenStringLiteral->new($this->{'text'},
                                       $this->{'chars'},
                                       $this->{'quotesLeft'},
                                       $this->{'quotesRight'});
}

sub getString
{
    shift->{'text'};
}

sub toString
{
    my $this = shift;
    my $buf = "[TokenStringLiteral] = ";
    if ($this->{'quotesLeft'} == 0) { $buf .= "("; }
    elsif ($this->{'quotesLeft'} == 1) { $buf .= "<"; }
    elsif ($this->{'quotesLeft'} == 3) { $buf .= "<<"; }
    else { die; }
    $buf .= $this->{'text'};
    if ($this->{'quotesRight'} == 0) { $buf .= ")"; }
    elsif ($this->{'quotesRight'} == 1) { $buf .= ">"; }
    elsif ($this->{'quotesRight'} == 3) { $buf .= ">>"; }
    else { die; }
    return $buf;
}

sub asHTML
{
    my ($this, $o) = @_;
    my $ret;
    $ret .= makeQuotes($this->{'quotesLeft'});
    $ret .= $this->{'chars'};
    $ret .= makeQuotes($this->{'quotesRight'});
    $o->write("<span class=\"s\">" . S2::BackendHTML::quoteHTML($ret) . "</span>");
}

sub scan
{
    my ($class, $t) = @_;

    my $inTriple = 0;
    my $continued = 0;
    my $pos = $t->getPos();

    if ($t->{'inString'} == 0) {
        # see if this is a triple quoted string,
        # like python.  if so, don't need to escape quotes
        $t->getRealChar();                # 1
        if ($t->peekChar() eq '"') {
            $t->getChar();                # 2
            if ($t->peekChar() eq '"') {
                $t->getChar();            # 3
                $inTriple = 1;
            } else {
                $t->{'inString'} = 0;
                return S2::TokenStringLiteral->new("", 1, 1);
            }
        }
    } elsif ($t->{'inString'} == 3) {
        $continued = 1;
        $inTriple = 1;
    } elsif ($t->{'inString'} == 1) {
        $continued = 1;
    }
    
    my $tbuf;  # text buffer (escaped)
    my $sbuf;  # source buffer
    
    while (1) {
        my $peekchar = $t->peekChar();
        if (! defined $peekchar) {
            die "Run-away string.  Check for unbalanced quotes on string literals.\n";
        } elsif ($peekchar eq '"') {
            if (! $inTriple) {
                $t->getChar();
                $t->{'inString'} = 0;
                return S2::TokenStringLiteral->new($tbuf, $sbuf, $continued ? 0 : 1, 1);
            } else {
                $t->getChar();                    # 1
                if ($t->peekChar() eq '"') {
                    $t->getChar();                # 2
                    if ($t->peekChar() eq '"') {
                        $t->getChar();            # 3
                        $t->{'inString'} = 0;
                        return S2::TokenStringLiteral->new($tbuf, $sbuf, $continued ? 0 : 3, 3);
                    } else {
                        $tbuf .= '""';
                        $sbuf .= '""';
                    }
                } else {
                    $tbuf .= '"';
                    $sbuf .= '"';
                }
            }
        } else {
            if ($t->peekChar() eq '$') {
                $t->{'inString'} = $inTriple ? 3 : 1;
                return S2::TokenStringLiteral->new($tbuf, $sbuf,
                           $continued ? 0 : ($inTriple ? 3 : 1),
                           0);
            }
            
            if ($t->peekChar() eq "\\") {
                $sbuf .= $t->getRealChar(); # skip the backslash.  next thing will be literal.
                $sbuf .= $t->peekChar();
                if ($t->peekChar() eq 'n') {
                    $t->forceNextChar("\n");
                }
                $tbuf .= $t->getRealChar();
            } else {
                my $c = $t->getRealChar();
                $tbuf .= $c;
                $sbuf .= $c;
            }
        }
    }
}

sub asS2
{
    my ($this, $o) = @_;
    $o->write(makesQuote($this->{'quotesLeft'}));
    $o->write(S2::Backend::quoteStringInner($this->{'text'}));
    $o->write(makesQuote($this->{'quotesRight'}));
}

sub asPerl
{
    my ($this, $bp, $o) = @_;
    $o->write($bp->quoteString($this->{'text'}));
}

sub makeQuotes
{
    my $i = shift;
    return "" if $i == 0;
    return "\"" if $i == 1;
    return "\"\"\"" if $i == 3;
    return "XXX";
}
                

1;

