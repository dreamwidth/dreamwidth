#!/usr/bin/perl
#
# DW::Autoscaler
#
# Pure, side-effect-free helpers for occupancy-based autoscaling of the web
# tier. Kept together (and free of AWS/memcached) so the controller in
# bin/worker/web-autoscaler can be unit-tested. Four concerns:
#
#   * delta()     - turn sharded memcached counter snapshots into per-tick
#                   growth, with per-shard reset detection.
#   * occupancy() - busy / (busy + idle) ratio for a tick.
#   * average()   - trailing-window mean, used to smooth occupancy samples so
#                   the controller reacts to a trend, not a single noisy tick.
#   * decide()    - the scaling decision for one service: a proportional target
#                   with asymmetric, hysteretic guards.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Autoscaler;

use strict;
use warnings;
use POSIX qw( ceil floor );

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

# average(\@samples, $window_secs, $now) -> mean value, or undef if none.
# @samples is an arrayref of [timestamp, value]; value may be undef (skipped).
sub average {
    my ( $samples, $window, $now ) = @_;
    my ( $sum, $count ) = ( 0, 0 );
    foreach my $s (@$samples) {
        next if $s->[0] < $now - $window;
        next unless defined $s->[1];
        $sum += $s->[1];
        $count++;
    }
    return undef unless $count;
    return $sum / $count;
}

# decide(\%in) -> { desired, action ('out'|'in'|'hold'), reason }
#
# Proportional target (desired = ceil(N * O / target)) with asymmetric,
# hysteretic guards: scale out fast (short window) but step- and cooldown-
# limited; scale in only below in_threshold, slowly. The band between
# in_threshold and target is a dead zone (no action) so the controller cannot
# oscillate.
sub decide {
    my ($in) = @_;
    my $n    = $in->{n};
    my $cap  = $in->{cap};
    my $flr  = $in->{floor};

    # Refuse to act on a malformed config rather than misbehaving: target is a
    # divisor (zero/undef => div-by-zero), and a missing floor/cap would let the
    # clamp below coerce desired to undef and potentially drain the service.
    return { desired => $n, action => 'hold', reason => 'config_error' }
        unless $in->{target}
        && $in->{target} > 0
        && defined $cap
        && defined $flr;

    my $clamp = sub {
        my $x = shift;
        $x = $cap if defined $cap && $x > $cap;
        $x = $flr if defined $flr && $x < $flr;
        return $x;
    };

    # ----- scale out? -----
    if ( defined $in->{o_out} && $in->{o_out} >= $in->{target} ) {
        my $raw = ceil( $n * $in->{o_out} / $in->{target} );
        if ( $raw > $n ) {
            return { desired => $n, action => 'hold', reason => 'out_cooldown' }
                if $in->{now} - $in->{last_out} < $in->{out_cooldown};

            my $step = $in->{out_step_min};
            my $pct  = ceil( $n * $in->{out_step_pct} );
            $step = $pct if $pct > $step;

            my $stepped = $n + $step;
            my $desired = $clamp->( $stepped < $raw ? $stepped : $raw );
            my $reason =
                  $desired >= $cap    ? 'out_capped'
                : ( $stepped < $raw ) ? 'out_step_limited'
                :                       'out';
            return {
                desired => $desired,
                action  => $desired > $n ? 'out' : 'hold',
                reason  => $reason,
            };
        }
    }

    # ----- scale in? -----
    if ( defined $in->{o_in} && $in->{o_in} <= $in->{in_threshold} ) {
        my $raw = ceil( $n * $in->{o_in} / $in->{target} );
        if ( $raw < $n ) {
            return { desired => $n, action => 'hold', reason => 'in_cooldown' }
                if $in->{now} - $in->{last_in} < $in->{in_cooldown};

            my $step = $in->{in_step_min};
            my $pct  = floor( $n * $in->{in_step_pct} );
            $step = $pct if $pct > $step;

            my $stepped = $n - $step;
            my $desired = $clamp->( $stepped > $raw ? $stepped : $raw );
            my $reason =
                  $desired <= $flr    ? 'in_floored'
                : ( $stepped > $raw ) ? 'in_step_limited'
                :                       'in';
            return {
                desired => $desired,
                action  => $desired < $n ? 'in' : 'hold',
                reason  => $reason,
            };
        }
    }

    return { desired => $n, action => 'hold', reason => 'deadzone' };
}

1;
