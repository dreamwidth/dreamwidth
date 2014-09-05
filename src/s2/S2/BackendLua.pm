#!/usr/bin/perl
#

package S2::BackendLua;

use strict;
use S2::Indenter;
use S2::BackendLua::Codegen;

sub new {
    my ($class, $l, $untrusted) = @_;
    my $this = {
        'layer' => $l,
        'untrusted' => $untrusted,
        'package' => '',
    };
    bless $this, $class;
}

sub getBuiltinPackage { shift->{'package'}; }
sub setBuiltinPackage { my $t = shift; $t->{'package'} = shift; }

sub getLayerID { shift->{'layerID'}; }
sub getLayerIDString { shift->{'layerID'}; }

sub untrusted { shift->{'untrusted'}; }

sub output {
    my ($this, $o) = @_;
    my $io = new S2::Indenter $o, 4;

    $io->writeln("local l = s2.makelayer()");
    my $nodes = $this->{'layer'}->getNodes();
    foreach my $n (@$nodes) {
        $n->asLua($this, $io);
    }
    $io->writeln("return l");
}

sub quoteString {
    shift if ref $_[0];
    my $s = shift;
    return "\"" . quoteStringInner($s) . "\"";
}

sub quoteStringInner {
    my $s = shift;
    $s =~ s/([\\\"])/\\$1/g;
    $s =~ s/\n/\\n/g;
    return $s;
}


1;
