#!/usr/bin/perl
#

package S2::NodeLayerInfo;

use strict;
use S2::Node;
use S2::NodeText;
use S2::TokenKeyword;
use S2::TokenPunct;
use vars qw($VERSION @ISA);

$VERSION = '1.0';
@ISA = qw(S2::Node);

sub new {
    my ($class) = @_;
    my $node = new S2::Node;
    bless $node, $class;
}

sub parse {
    my ($class, $toker) = @_;
    my $n = new S2::NodeLayerInfo;

    my ($nkey, $nval);

    $n->requireToken($toker, $S2::TokenKeyword::LAYERINFO);
    $n->addNode($nkey = S2::NodeText->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::ASSIGN);
    $n->addNode($nval = S2::NodeText->parse($toker));
    $n->requireToken($toker, $S2::TokenPunct::SCOLON);

    $n->{'key'} = $nkey->getText();
    $n->{'val'} = $nval->getText();

    return $n;
}

sub canStart {
    my ($class, $toker) = @_;
    return $toker->peek() == $S2::TokenKeyword::LAYERINFO;
}

sub getKey { shift->{'key'}; }
sub getValue { shift->{'val'}; }

sub asS2 {
    my ($this, $o) = @_;
    $o->tabwrite("layerinfo ");
    $o->write(S2::Backend::quoteString($this->{'key'}));
    $o->write(" = ");
    $o->write(S2::Backend::quoteString($this->{'val'}));
    $o->writeln(";");
}

sub asPerl {
    my ($this, $bp, $o) = @_;
    
    if ($bp->oo) {
        $o->tabwriteln("\$lay->set_layer_info(" .
                       $bp->quoteString($this->{'key'}) . "," .
                       $bp->quoteString($this->{'val'}) . ");");
    }
    else {
        $o->tabwriteln("set_layer_info(" .
                       $bp->getLayerIDString() . "," .
                       $bp->quoteString($this->{'key'}) . "," .
                       $bp->quoteString($this->{'val'}) . ");");
    }
}

sub check {
    my ($this, $l, $ck) = @_;
    $l->setLayerInfo($this->{'key'}, $this->{'val'});
}

