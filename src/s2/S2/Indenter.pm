#!/usr/bin/perl
#

package S2::Indenter;

use strict;

sub new {
    my ($class, $o, $tabsize) = @_;
    my $this = {
        'o' => $o,
        'tabsize' => $tabsize,
        'depth' => 0,
    };
    bless $this, $class;
}

sub write {
    my ($this, $s) = @_;
    $this->{'o'}->write($s);
}

sub writeln {
    my ($this, $s) = @_;
    $this->{'o'}->writeln($s);
}

sub tabwrite {
    my ($this, $s) = @_;
    $this->{'o'}->write(" "x($this->{'tabsize'}*$this->{'depth'}) . $s);
}

sub tabwriteln {
    my ($this, $s) = @_;
    $this->{'o'}->writeln(" "x($this->{'tabsize'}*$this->{'depth'}) . $s);
}

sub newline { shift->{'o'}->newline(); }

sub tabIn { shift->{'depth'}++; }
sub tabOut { shift->{'depth'}--; }

1;
