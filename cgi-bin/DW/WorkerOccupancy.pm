#!/usr/bin/perl
#
# DW::WorkerOccupancy
#
# Per-worker busy/idle accounting for occupancy-based autoscaling. Each Starman
# worker records, per request, the time it spent BUSY (serving) and the IDLE gap
# since it last finished, into sharded memcached atomic counters. The autoscaler
# reads these to compute pool occupancy = busy/(busy+idle).
#
# No shared memory: each preforked worker keeps its own $last_end and always
# writes to its own shard (PID % 64), so there is no cross-worker key contention.
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

package DW::WorkerOccupancy;

use strict;
use warnings;
use Time::HiRes ();

# We write busy/idle into memcached counters directly; load it explicitly
# rather than relying on ljlib.pl having pulled it in first.
use LJ::MemCache;

# Injectable clock (overridden in tests).
our $CLOCK = \&Time::HiRes::time;

my $SHARDS = 64;

my $last_end;     # epoch float when this worker last finished a request
my $req_start;    # epoch float when the current request started

# Test-only state reset.
sub __reset {
    $last_end  = undef;
    $req_start = undef;
    return;
}

sub _svc { return $ENV{DW_LOKI_SERVICE} }

sub _key {
    my ($kind) = @_;
    my $svc = _svc();
    return undef unless defined $svc && length $svc;
    return "dw:sched:${kind}:${svc}:" . ( $$ % $SHARDS );
}

# Atomic increment with lazy initialization. A successful incr returns the new
# (always positive) counter value; a missing key returns a falsy value (undef
# from real memcached, 0 from the in-process fake used in tests). Treat any
# falsy result as "needs init": create the key with add, and if another worker
# beat us to the add, fall back to incr so no contribution is lost.
sub _incr {
    my ( $kind, $amount ) = @_;
    return if $amount <= 0;
    my $key = _key($kind);
    return unless defined $key;
    my $rv = LJ::MemCache::incr( $key, $amount );
    unless ($rv) {

        # No expiry by design: these are monotonic counters read by the
        # autoscaler as per-tick deltas, and it detects/reseeds any shard whose
        # value drops (LRU eviction, flush, restart), so stale keys are harmless.
        LJ::MemCache::add( $key, $amount )
            or LJ::MemCache::incr( $key, $amount );
    }
    return;
}

# When no service is configured (dev / non-ECS) this module is a total no-op:
# we don't even touch the per-worker timing state, so that turning the service
# on later within the same process can't observe a stale half-started request.
sub _enabled {
    my $svc = _svc();
    return defined $svc && length $svc;
}

# Call at the very start of request handling.
sub request_start {
    return unless _enabled();
    my $now = $CLOCK->();
    if ( defined $last_end ) {
        _incr( 'idle_ms', int( ( $now - $last_end ) * 1000 + 0.5 ) );
    }
    $req_start = $now;
    return;
}

# Call at the very end of request handling.
sub request_end {
    return unless _enabled();
    my $now = $CLOCK->();
    if ( defined $req_start ) {
        _incr( 'busy_ms', int( ( $now - $req_start ) * 1000 + 0.5 ) );
    }
    $last_end  = $now;
    $req_start = undef;
    return;
}

1;
