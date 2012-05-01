#!/usr/bin/perl
#

package S2::TokenPunct;

use strict;
use S2::Token;
use vars qw($VERSION @ISA
            $LT $LTE $GTE $GT $EQ $NE $ASSIGN $INCR $PLUS
            $DEC $MINUS $DEREF $SCOLON $COLON $DCOLON $LOGAND
            $BITAND $LOGOR $BITOR $MULT $DIV $MOD $NOT $DOT
            $DOTDOT $LBRACE $RBRACE $LBRACK $RBRACK $LPAREN
            $RPAREN $COMMA $QMARK $DOLLAR $HASSOC
            %finals
            );

$VERSION = '1.0';
@ISA = qw(S2::Token);

$LTE    = new S2::TokenPunct '<=', 1;
$LT     = new S2::TokenPunct '<', 1;
$GTE    = new S2::TokenPunct '>=', 1;
$GT     = new S2::TokenPunct '>', 1;
$EQ     = new S2::TokenPunct "==", 1;
$HASSOC = new S2::TokenPunct "=>", 1;
$ASSIGN = new S2::TokenPunct "=", 1;
$NE     = new S2::TokenPunct "!=", 1;
$INCR   = new S2::TokenPunct "++", 1;
$PLUS   = new S2::TokenPunct "+", 1;
$DEC    = new S2::TokenPunct "--", 1;
$MINUS  = new S2::TokenPunct "-", 1;
$DEREF  = new S2::TokenPunct "->", 1;
$SCOLON = new S2::TokenPunct ";", 1;
$DCOLON = new S2::TokenPunct "::", 1;
$COLON  = new S2::TokenPunct ":", 1;
$LOGAND = new S2::TokenPunct "&&", 1;
$BITAND = new S2::TokenPunct "&", 1;
$LOGOR  = new S2::TokenPunct "||", 1;
$BITOR  = new S2::TokenPunct "|", 1;
$MULT   = new S2::TokenPunct "*", 1;
$DIV    = new S2::TokenPunct "/", 1;
$MOD    = new S2::TokenPunct "%", 1;
$NOT    = new S2::TokenPunct "!", 1;
$DOT    = new S2::TokenPunct ".", 1;
$DOTDOT = new S2::TokenPunct "..", 1;
$LBRACE = new S2::TokenPunct "{", 1;
$RBRACE = new S2::TokenPunct "}", 1;
$LBRACK = new S2::TokenPunct "[", 1;
$RBRACK = new S2::TokenPunct "]", 1;
$LPAREN = new S2::TokenPunct "(", 1;
$RPAREN = new S2::TokenPunct ")", 1;
$COMMA  = new S2::TokenPunct ",", 1;
$QMARK  = new S2::TokenPunct "?", 1;
$DOLLAR = new S2::TokenPunct '$', 1;

sub new
{
    my ($class, $punct, $final) = @_;
    return $finals{$punct} if defined $finals{$punct};
    my $this = { 'chars' => $punct };
    $finals{$punct} = $this if $final;
    bless $this, $class;
}

sub getPunct { shift->{'chars'}; }

sub asHTML
{
    my ($this, $o) = @_;
    if ($this->{'chars'} =~ m![\[\]\(\)\{\}]!) {
        $o->write("<span class=\"b\">$this->{'chars'}</span>");
    } else {
        $o->write("<span class=\"p\">" . S2::BackendHTML::quoteHTML($this->{'chars'}) . "</span>");
    }
}

sub asS2
{
    my ($this, $o) = @_;
    $o->write($this->{'chars'});
}

sub toString
{
    my $this = shift;
    "[TokenPunct] = $this->{'chars'}";
}

1;

