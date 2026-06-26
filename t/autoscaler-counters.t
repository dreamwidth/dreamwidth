#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 6;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Autoscaler::Counters;

# First sight of shards: no delta, baselines seeded.
{
    my ( $d, $nb ) = DW::Autoscaler::Counters::delta( {}, { a => 100, b => 50 } );
    is( $d, 0, 'first sight yields zero delta' );
    is_deeply( $nb, { a => 100, b => 50 }, 'baselines seeded to current' );
}

# Normal growth across two shards.
{
    my ( $d, $nb ) =
        DW::Autoscaler::Counters::delta( { a => 100, b => 50 }, { a => 130, b => 90 } );
    is( $d, 70, 'delta sums per-shard growth (30 + 40)' );
    is_deeply( $nb, { a => 130, b => 90 }, 'new baselines = current' );
}

# Per-shard reset: shard b dropped (node flush) => contributes 0, not negative.
{
    my ( $d, $nb ) =
        DW::Autoscaler::Counters::delta( { a => 100, b => 500 }, { a => 120, b => 5 } );
    is( $d, 20, 'reset shard contributes 0; only shard a counts' );
}

# Occupancy ratio.
is( DW::Autoscaler::Counters::occupancy( 700, 300 ), 0.7, 'occupancy = busy/(busy+idle)' );
