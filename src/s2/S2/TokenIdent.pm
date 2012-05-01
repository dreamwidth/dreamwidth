#!/usr/bin/perl
#

package S2::TokenIdent;

use strict;
use S2::Token;
use S2::TokenKeyword;
use vars qw($VERSION @ISA $DEFAULT $TYPE $STRING);

$VERSION = '1.0';
@ISA = qw(S2::Token);

# numeric values for $this->{'type'}
$DEFAULT = 0;
$TYPE    = 1;
$STRING  = 2;

sub new 
{
    my ($class, $ident) = @_;
    my $kwtok = S2::TokenKeyword->tokenFromString($ident);
    return $kwtok if $kwtok;
    bless {
        'chars' => $ident,
    }, $class;
}

sub getIdent {
    shift->{'chars'};
}

sub toString {
    my $this = shift;
    "[TokenIdent] = $this->{'chars'}";
}

sub setType {
    my ($this, $type) = @_;
    $this->{'type'} = $type;
}

sub asHTML {
    my ($this, $o) = @_;
    my $ident = $this->{'chars'};
    # FIXME: TODO: Don't hardcode internal types, intelligently recognise
    #              places where types and class references occur and
    #              make them class="t"
    if ($ident =~ /^(int|string|void|bool)$/) {
        $o->write("<span class=\"t\">$ident</span>");
    } else {
        $o->write("<span class=\"i\">$ident</span>");
    }
}

1;

