#!/usr/bin/perl
#
# t/autoscaler.t
#
# Tests for DW::Autoscaler: counters/occupancy, trailing-window average, and
# the scaling decision.
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

use strict;
use warnings;
use Test::More tests => 31;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Autoscaler;

# ---------------------------------------------------------------------------
# delta() / occupancy()
# ---------------------------------------------------------------------------

# First sight of shards: no delta, baselines seeded.
{
    my ( $d, $nb ) = DW::Autoscaler::delta( {}, { a => 100, b => 50 } );
    is( $d, 0, 'first sight yields zero delta' );
    is_deeply( $nb, { a => 100, b => 50 }, 'baselines seeded to current' );
}

# Normal growth across two shards.
{
    my ( $d, $nb ) = DW::Autoscaler::delta( { a => 100, b => 50 }, { a => 130, b => 90 } );
    is( $d, 70, 'delta sums per-shard growth (30 + 40)' );
    is_deeply( $nb, { a => 130, b => 90 }, 'new baselines = current' );
}

# Per-shard reset: shard b dropped (node flush) => contributes 0, not negative.
{
    my ( $d, $nb ) = DW::Autoscaler::delta( { a => 100, b => 500 }, { a => 120, b => 5 } );
    is( $d, 20, 'reset shard contributes 0; only shard a counts' );
}

# Occupancy ratio.
is( DW::Autoscaler::occupancy( 700, 300 ), 0.7, 'occupancy = busy/(busy+idle)' );

# ---------------------------------------------------------------------------
# average()
# ---------------------------------------------------------------------------
{
    my $now     = 1000;
    my @samples = ( [ 940, 0.2 ], [ 970, 0.4 ], [ 990, 0.9 ], [ 1000, 1.0 ] );

    # 45s window: only ts >= 955 -> (0.4, 0.9, 1.0) avg = 0.766...
    my $w = DW::Autoscaler::average( \@samples, 45, $now );
    ok( abs( $w - ( ( 0.4 + 0.9 + 1.0 ) / 3 ) ) < 1e-9, '45s window averages last three' );

    # 300s window: all four -> 0.625
    is( DW::Autoscaler::average( \@samples, 300, $now ), 0.625, '300s window averages all' );

    # undef samples are skipped
    my @withundef = ( [ 990, undef ], [ 1000, 0.8 ] );
    is( DW::Autoscaler::average( \@withundef, 45, $now ), 0.8, 'undef samples skipped' );

    # no samples in window -> undef
    is( DW::Autoscaler::average( [ [ 100, 0.5 ] ], 45, $now ), undef, 'empty window => undef' );
}

# ---------------------------------------------------------------------------
# decide()
# ---------------------------------------------------------------------------

# Baseline config the tests tweak per-case.
sub base {
    return {
        n            => 10,
        o_out        => 0.5,
        o_in         => 0.5,
        target       => 0.70,
        in_threshold => 0.50,
        out_step_pct => 0.5,
        out_step_min => 1,
        in_step_pct  => 0.10,
        in_step_min  => 1,
        floor        => 5,
        cap          => 20,
        now          => 10_000,
        last_out     => 0,
        last_in      => 0,
        out_cooldown => 60,
        in_cooldown  => 300,
        @_,
    };
}

# Deadzone: occupancy between in_threshold and target -> hold.
{
    my $d = DW::Autoscaler::decide( base( o_out => 0.6, o_in => 0.6 ) );
    is( $d->{action},  'hold', 'deadzone holds' );
    is( $d->{desired}, 10,     'deadzone keeps N' );
}

# Scale out, step-limited: raw = ceil(10*1.0/0.7)=15, step cap = +5 -> 15 (both 15).
{
    my $d = DW::Autoscaler::decide( base( o_out => 1.0 ) );
    is( $d->{action},  'out', 'high occupancy scales out' );
    is( $d->{desired}, 15,    'scales by min(raw, N+step) = 15' );
}

# Scale out capped: N=18, raw large, cap=20 -> 20.
{
    my $d = DW::Autoscaler::decide( base( n => 18, o_out => 1.0 ) );
    is( $d->{desired}, 20, 'scale out clamped to cap' );
}

# Scale out blocked by cooldown.
{
    my $d = DW::Autoscaler::decide( base( o_out => 1.0, last_out => 9_990 ) );
    is( $d->{action}, 'hold', 'out cooldown blocks scaling' );
}

# Scale in, step-limited: o_in=0.2 -> raw=ceil(10*0.2/0.7)=3, in_step=max(1,floor(1))=1 -> 9.
{
    my $d = DW::Autoscaler::decide( base( o_in => 0.2, o_out => 0.2 ) );
    is( $d->{action},  'in', 'low occupancy scales in' );
    is( $d->{desired}, 9,    'scales in by one step' );
}

# Scale in blocked by cooldown.
{
    my $d = DW::Autoscaler::decide( base( o_in => 0.2, o_out => 0.2, last_in => 9_900 ) );
    is( $d->{action}, 'hold', 'in cooldown blocks scaling' );
}

# No traffic: undef occupancy on both windows -> hold, never touches arithmetic.
{
    my $d = DW::Autoscaler::decide( base( o_out => undef, o_in => undef ) );
    is( $d->{action}, 'hold',     'undef occupancy holds (no-traffic contract)' );
    is( $d->{reason}, 'deadzone', 'undef occupancy reported as deadzone' );
}

# Scale in clamped to floor: o_in=0 wants 0 tasks, floor=5 caps the drain.
{
    my $d = DW::Autoscaler::decide( base( n => 6, o_in => 0, o_out => 0 ) );
    is( $d->{desired}, 5,            'scale in clamped to floor' );
    is( $d->{reason},  'in_floored', 'floor clamp reported' );
}

# Out step limit actually binds when out_step_pct is tight: step=+1 -> 11, raw=15.
{
    my $d = DW::Autoscaler::decide( base( o_out => 1.0, out_step_pct => 0.1 ) );
    is( $d->{desired}, 11, 'tight step cap limits scale out' );
    is( $d->{reason}, 'out_step_limited', 'step-limited reason reported' );
}

# In-step percentage engages at larger N: n=20, 10% -> step 2 (not the min of 1).
{
    my $d = DW::Autoscaler::decide( base( n => 20, o_in => 0.2, o_out => 0.2 ) );
    is( $d->{desired}, 18, 'in step is floor(20*0.10)=2, so 20->18' );
    is( $d->{reason}, 'in_step_limited', 'in step-limited reason reported' );
}

# Malformed config (target 0) holds instead of dividing by zero.
{
    my $d = DW::Autoscaler::decide( base( target => 0, o_out => 1.0 ) );
    is( $d->{action}, 'hold',         'zero target does not crash' );
    is( $d->{reason}, 'config_error', 'zero target reported as config_error' );
}

# Malformed config (missing cap) holds rather than clamping desired to undef.
{
    my $d = DW::Autoscaler::decide( base( cap => undef, o_out => 1.0 ) );
    is( $d->{action},  'hold', 'missing cap does not act' );
    is( $d->{desired}, 10,     'missing cap leaves desired at N' );
}
