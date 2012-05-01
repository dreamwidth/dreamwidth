#!/usr/bin/perl
#

package S2::TokenWhitespace;

use strict;
use S2::Token;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Token);

sub new {
    my ($class, $ws) = @_;
    my $this = {
        'chars' => $ws,
    };
    bless $this, $class;
}

sub isNecessary { 0; }

sub getWhiteSpace { 
    my $this = shift;
    $this->{'chars'};
}

sub toString {
    return "[TokenWhitespace]";
}

sub asHTML {
    my ($this, $o) = @_;
    $o->write($this->{'chars'});
}

1;

