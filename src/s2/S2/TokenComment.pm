#!/usr/bin/perl
#

package S2::TokenComment;

use strict;
use S2::Token;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Token);

sub new
{
    my ($class, $com) = @_;
    bless {
        'chars' => $com,
    }, $class;
}

sub getComment
{
    shift->{'chars'};
}

sub toString
{
    "[TokenComment]";
}

sub isNecessary { return 0; }

sub asHTML
{
    my ($this, $o) = @_;
    $o->write("<span class=\"c\">" . S2::BackendHTML::quoteHTML($this->{'chars'}) . "</span>");
}

1;

