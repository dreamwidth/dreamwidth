#!/usr/bin/perl
#

package S2::Layer;

use S2::NodeUnnecessary;
use S2::NodeLayerInfo;
use S2::NodeProperty;
use S2::NodePropGroup;
use S2::NodeSet;
use S2::NodeFunction;
use S2::NodeClass;

sub new
{
    my ($class, $toker, $type) = @_;
    my $this = bless {
        type => $type,
        declaredType => undef,
        nodes => [],
        layerinfo => {},
    }, $class;

    my $nodes = $this->{'nodes'};

    while (my $t = $toker->peek()) {

        if (S2::NodeUnnecessary->canStart($toker)) {
            push @$nodes, S2::NodeUnnecessary->parse($toker);
            next;
        }

        if (S2::NodeLayerInfo->canStart($toker)) {
            my $nli = S2::NodeLayerInfo->parse($toker);
            push @$nodes, $nli;
            if ( $nli->getKey eq "type" ) {
                $this->{declaredType} = $nli->getValue;
            }
            $this->setLayerInfo($nli->getKey, $nli->getValue);
            next;
        }

        if (S2::NodeProperty->canStart($toker)) {
            push @$nodes, S2::NodeProperty->parse($toker);
            next;
        }

        if (S2::NodePropGroup->canStart($toker)) {
            push @$nodes, S2::NodePropGroup->parse($toker);
            next;
        }

        if (S2::NodeSet->canStart($toker)) {
            push @$nodes, S2::NodeSet->parse($toker);
            next;
        }

        if (S2::NodeFunction->canStart($toker)) {
            push @$nodes, S2::NodeFunction->parse($toker);
            next;
        }

        if (S2::NodeClass->canStart($toker)) {
            push @$nodes, S2::NodeClass->parse($toker);
            next;
        }

        S2::error($t, "Unknown token encountered while parsing layer: " .
                  $t->toString());
    }
    
    return $this;
}

sub setLayerInfo {
    my ($this, $key, $val) = @_;
    $this->{'layerinfo'}->{$key} = $val;
}

sub getLayerInfo {
    my ($this, $key) = @_;
    $this->{'layerinfo'}->{$key};
}

sub getLayerInfoKeys {
    my ($this) = @_;
    return [ keys %{$this->{'layerinfo'}} ];
}

sub getType {
    shift->{'type'};
}

sub getDeclaredType {
    shift->{'declaredType'};
}

sub setType {
    shift->{'type'} = shift;
}

sub toString {
    shift->{'type'};
}

sub getNodes {
    return shift->{'nodes'};
}

sub isCoreOrLayout { # or markup!
    my $this = shift;
    return $this->{'type'} eq "core" ||
        $this->{'type'} eq "markup" ||
        $this->{'type'} eq "layout";
}

1;
