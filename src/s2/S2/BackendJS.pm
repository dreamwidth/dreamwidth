#!/usr/bin/perl
#

package S2::BackendJS;

use strict;
use S2::Indenter;
use S2::BackendJS::Codegen;
use Carp;

# $opts:
#    'docs' - set to true to produce code to register
#            layer documentation. (FIXME: Not yet implemented)
#    'propmeta' - set to true to include property metadata,
#            which is needed for property editing but is not
#            needed at runtime.
sub new {
    my ($class, $l, $layervar, $untrusted, $opts) = @_;
    my $this = {
        'layer' => $l,
        'layerid' => $layervar,
        'untrusted' => $untrusted,
        'package' => '',
        'opts' => $opts || {},        
    };
    bless $this, $class;
}

sub getBuiltinPackage { shift->{'package'}; }
sub setBuiltinPackage { my $t = shift; $t->{'package'} = shift; }

sub getLayerVar { shift->{'layerid'}; }
sub getLayerVar { shift->{'layerid'}; }

sub untrusted { shift->{'untrusted'}; }

sub output {
    my ($this, $o) = @_;
    my $io = new S2::Indenter $o, 4;

    $io->writeln("var $this->{layerid} = s2.makeLayer();");
    my $nodes = $this->{'layer'}->getNodes();
    foreach my $n (@$nodes) {
        $n->asJS($this, $io);
    }
#    $io->writeln("return l");
}

# JavaScript has function-level scope while S2 has block-level
# scope. Therefore we must decorate all local variables with
# a scope identifier to ensure there are no collisions between
# blocks.
sub decorateLocal {
    my ($this, $varname, $scope) = @_;
    
    # HACK: Use part of Perl's stringification of the
    # owning block to decorate the variable name. Should
    # do something better later.
    my $decorate;
    my $block = $scope."";
    if ($block =~ /HASH\(0x(\w+)\)/) {
        $decorate = $1;
    }
    else {
        croak "Unable to decorate $varname in $block";
    }

    return "__".$decorate."_".$varname;
}

# To avoid conflict with JavaScript's reserved words, all
# bare identifiers must be decorated.
# Local variables should use decorateLocal (above) instead.
sub decorateIdent {
    my ($this, $varname) = @_;
    
    return "_".$varname;
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
