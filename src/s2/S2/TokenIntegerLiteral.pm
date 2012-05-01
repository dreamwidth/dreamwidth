#!/usr/bin/perl
#

package S2::TokenIntegerLiteral;

use strict;
use S2::Token;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Token);

sub new
{
    my ($class, $val) = @_;
    bless {
        'chars' => $val+0,
    };
}

sub getInteger
{
    my $this = shift;
    $this->{'chars'};
}

sub asS2
{
    my ($this, $o) = @_;
    $o->write($this->{'chars'});
}

sub asHTML
{
    my ($this, $o) = @_;
    $o->write("<span class=\"n\">$this->{'chars'}</span>");
}

sub asPerl
{
    my ($this, $bp, $o) = @_;
    $o->write($this->{'chars'});
}

sub toString
{
    my $this = shift;
    "[TokenIntegerLiteral] = $this->{'chars'}";
}


1;

