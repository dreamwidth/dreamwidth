#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 21;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Autoscaler::Decision;

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
    my $d = DW::Autoscaler::Decision::decide( base( o_out => 0.6, o_in => 0.6 ) );
    is( $d->{action},  'hold', 'deadzone holds' );
    is( $d->{desired}, 10,     'deadzone keeps N' );
}

# Scale out, step-limited: raw = ceil(10*1.0/0.7)=15, step cap = +5 -> 15 (both 15).
{
    my $d = DW::Autoscaler::Decision::decide( base( o_out => 1.0 ) );
    is( $d->{action},  'out', 'high occupancy scales out' );
    is( $d->{desired}, 15,    'scales by min(raw, N+step) = 15' );
}

# Scale out capped: N=18, raw large, cap=20 -> 20.
{
    my $d = DW::Autoscaler::Decision::decide( base( n => 18, o_out => 1.0 ) );
    is( $d->{desired}, 20, 'scale out clamped to cap' );
}

# Scale out blocked by cooldown.
{
    my $d = DW::Autoscaler::Decision::decide( base( o_out => 1.0, last_out => 9_990 ) );
    is( $d->{action}, 'hold', 'out cooldown blocks scaling' );
}

# Scale in, step-limited: o_in=0.2 -> raw=ceil(10*0.2/0.7)=3, in_step=max(1,floor(1))=1 -> 9.
{
    my $d = DW::Autoscaler::Decision::decide( base( o_in => 0.2, o_out => 0.2 ) );
    is( $d->{action},  'in', 'low occupancy scales in' );
    is( $d->{desired}, 9,    'scales in by one step' );
}

# Scale in blocked by cooldown.
{
    my $d = DW::Autoscaler::Decision::decide( base( o_in => 0.2, o_out => 0.2, last_in => 9_900 ) );
    is( $d->{action}, 'hold', 'in cooldown blocks scaling' );
}

# No traffic: undef occupancy on both windows -> hold, never touches arithmetic.
{
    my $d = DW::Autoscaler::Decision::decide( base( o_out => undef, o_in => undef ) );
    is( $d->{action}, 'hold',     'undef occupancy holds (no-traffic contract)' );
    is( $d->{reason}, 'deadzone', 'undef occupancy reported as deadzone' );
}

# Scale in clamped to floor: o_in=0 wants 0 tasks, floor=5 caps the drain.
{
    my $d = DW::Autoscaler::Decision::decide( base( n => 6, o_in => 0, o_out => 0 ) );
    is( $d->{desired}, 5,            'scale in clamped to floor' );
    is( $d->{reason},  'in_floored', 'floor clamp reported' );
}

# Out step limit actually binds when out_step_pct is tight: step=+1 -> 11, raw=15.
{
    my $d = DW::Autoscaler::Decision::decide( base( o_out => 1.0, out_step_pct => 0.1 ) );
    is( $d->{desired}, 11, 'tight step cap limits scale out' );
    is( $d->{reason}, 'out_step_limited', 'step-limited reason reported' );
}

# In-step percentage engages at larger N: n=20, 10% -> step 2 (not the min of 1).
{
    my $d = DW::Autoscaler::Decision::decide( base( n => 20, o_in => 0.2, o_out => 0.2 ) );
    is( $d->{desired}, 18, 'in step is floor(20*0.10)=2, so 20->18' );
    is( $d->{reason}, 'in_step_limited', 'in step-limited reason reported' );
}

# Malformed config (target 0) holds instead of dividing by zero.
{
    my $d = DW::Autoscaler::Decision::decide( base( target => 0, o_out => 1.0 ) );
    is( $d->{action}, 'hold',         'zero target does not crash' );
    is( $d->{reason}, 'config_error', 'zero target reported as config_error' );
}

# Malformed config (missing cap) holds rather than clamping desired to undef.
{
    my $d = DW::Autoscaler::Decision::decide( base( cap => undef, o_out => 1.0 ) );
    is( $d->{action},  'hold', 'missing cap does not act' );
    is( $d->{desired}, 10,     'missing cap leaves desired at N' );
}
