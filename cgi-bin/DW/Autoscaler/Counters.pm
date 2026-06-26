#!/usr/bin/perl
#
# DW::Autoscaler::Counters
#
# Pure helpers for turning sharded memcached counter snapshots into per-tick
# deltas, with per-shard reset detection, and into an occupancy ratio.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.

package DW::Autoscaler::Counters;

use strict;
use warnings;

# delta(\%prev, \%cur) -> ($sum_delta, \%new_baselines)
# Sums per-shard growth. A shard whose current value is below its baseline
# (memcached flush/eviction/restart) contributes 0 and is reseeded. Shards seen
# for the first time contribute 0 this tick but seed a baseline.
sub delta {
    my ( $prev, $cur ) = @_;
    my $sum = 0;
    my %new = %$cur;
    foreach my $k ( keys %$cur ) {
        next unless defined $prev->{$k};
        my $d = $cur->{$k} - $prev->{$k};
        $sum += $d if $d >= 0;
    }
    return ( $sum, \%new );
}

# occupancy($delta_busy, $delta_idle) -> ratio in [0,1], or undef if no samples.
sub occupancy {
    my ( $busy, $idle ) = @_;
    my $total = $busy + $idle;
    return undef unless $total > 0;
    return $busy / $total;
}

1;
