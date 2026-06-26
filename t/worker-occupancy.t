#!/usr/bin/perl
# Tests for DW::WorkerOccupancy
use strict;
use warnings;
use Test::More tests => 9;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(with_fake_memcache);
use DW::WorkerOccupancy;

# Controllable clock
my $t = 1000.0;
local $DW::WorkerOccupancy::CLOCK = sub { $t };
local $ENV{DW_LOKI_SERVICE} = 'web-test';

my $shard    = $$ % 64;
my $busy_key = "dw:sched:busy_ms:web-test:$shard";
my $idle_key = "dw:sched:idle_ms:web-test:$shard";

with_fake_memcache {
    DW::WorkerOccupancy::__reset();

    # First request: busy recorded, NO idle (no prior request)
    DW::WorkerOccupancy::request_start();
    $t = 1000.5;    # 500ms of work
    DW::WorkerOccupancy::request_end();
    is( LJ::MemCache::get($busy_key), 500,   'first request records 500ms busy' );
    is( LJ::MemCache::get($idle_key), undef, 'first request records no idle' );

    # Idle gap of 2.0s, then a 250ms second request
    $t = 1002.5;
    DW::WorkerOccupancy::request_start();
    is( LJ::MemCache::get($idle_key), 2000, 'idle gap of 2000ms recorded' );
    $t = 1002.75;
    DW::WorkerOccupancy::request_end();
    is( LJ::MemCache::get($busy_key), 750, 'busy accumulates to 750ms' );

    # Counters accumulate across requests. The cold-key path (incr falsy -> add)
    # is exercised by the first request above; the warm path (incr succeeds) is
    # exercised here on the now-existing keys.
    $t = 1003.0;
    DW::WorkerOccupancy::request_start();
    is( LJ::MemCache::get($idle_key), 2250, 'idle accumulates to 2250ms' );
    $t = 1003.1;
    DW::WorkerOccupancy::request_end();
    is( LJ::MemCache::get($busy_key), 850, 'busy accumulates to 850ms' );
};

# No service env => total no-op (dev / non-ECS)
with_fake_memcache {
    DW::WorkerOccupancy::__reset();
    local $ENV{DW_LOKI_SERVICE};
    delete $ENV{DW_LOKI_SERVICE};
    DW::WorkerOccupancy::request_start();
    $t = 1003.6;
    DW::WorkerOccupancy::request_end();
    is( LJ::MemCache::get($busy_key), undef, 'no service => no busy write' );
    is( LJ::MemCache::get($idle_key), undef, 'no service => no idle write' );
};

ok( ( $$ % 64 ) == $shard, 'shard is PID mod 64' );
