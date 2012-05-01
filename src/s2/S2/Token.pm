#!/usr/bin/perl
#

package S2::Token;

use strict;

sub getFilePos {
    return $_[0]->{'pos'};
}

sub isNecessary { 1; }

sub toString {
    die "Abstract! " . Data::Dumper::Dumper(@_);
}

sub asHTML {
    my $this = shift;
    die "No asHTML defined for " . ref $this;
}

sub asS2 {
    my ($this, $o) = @_; # Indenter o
    $o->write("##Token::asS2##");
}

sub asPerl {
    my ($this, $bp, $o) = @_; # BackendPerl bp, Indenter o
    $o->write("##Token::asPerl##");
}




1;
