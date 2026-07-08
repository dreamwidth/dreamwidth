# t/request-cache.t
#
# Tests for DW::RequestCache: the KV memoization API, the registration API, and
# the clear() guarantee that LJ::start_request and the task worker loop rely on
# to isolate one request/job from the next.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::RequestCache;

# ---- KV store API ----

DW::RequestCache->set( 'ns', 'k', 'v' );
is( DW::RequestCache->get( 'ns', 'k' ), 'v', 'get returns the set value' );
ok( DW::RequestCache->has( 'ns', 'k' ), 'has is true for a present key' );
ok( !DW::RequestCache->has( 'ns', 'x' ), 'has is false for an absent key' );
is( DW::RequestCache->get( 'ns', 'x' ), undef, 'get is undef for an absent key' );

# a read miss must not autovivify the namespace (would inflate memory silently)
DW::RequestCache->get( 'never', 'k' );
ok( !DW::RequestCache->has( 'never', 'k' ), 'get does not autovivify the namespace' );

# memoize computes once and caches, including a false result
my $calls = 0;
my $code  = sub { $calls++; return 0 };
is( DW::RequestCache->memoize( 'm', 'k', $code ), 0, 'memoize returns the computed value' );
is( DW::RequestCache->memoize( 'm', 'k', $code ), 0, 'memoize returns the cached value' );
is( $calls, 1, 'memoize computes exactly once, caching even a false value' );

# remove and clear_ns
DW::RequestCache->set( 'ns', 'k2', 'v2' );
DW::RequestCache->remove( 'ns', 'k' );
ok( !DW::RequestCache->has( 'ns', 'k' ), 'remove drops the target key' );
ok( DW::RequestCache->has( 'ns', 'k2' ), 'remove leaves sibling keys' );
DW::RequestCache->clear_ns('ns');
ok( !DW::RequestCache->has( 'ns', 'k2' ), 'clear_ns drops the whole namespace' );

# ---- registration API + registered() ----

my %test_hash  = ( a => 1 );
my @test_array = ( 1, 2, 3 );
my $reset_ran  = 0;
DW::RequestCache->register_var( 't_hash',  \%test_hash );
DW::RequestCache->register_var( 't_array', \@test_array );
DW::RequestCache->register_reset( 't_reset', sub { $reset_ran++ } );

my %reg = map { $_->{name} => $_ } DW::RequestCache->registered;
ok( $reg{request_cache_store},     'registered includes the KV store' );
ok( $reg{t_hash} && $reg{t_array}, 'registered includes register_var entries' );
ok( !$reg{t_reset},                'registered omits register_reset entries (nothing to sample)' );
is( ref $reg{t_hash}->{getref}->(), 'HASH', 'a registered getref returns the underlying ref' );

# ---- the guarantee: clear() empties everything routed through the module ----

DW::RequestCache->set( 'm', 'survives', 'until clear' );
ok( DW::RequestCache->has( 'm', 'survives' ), 'store is populated before clear' );

DW::RequestCache->clear;

ok( !DW::RequestCache->has( 'm', 'survives' ), 'clear empties the KV store' );
is_deeply( \%test_hash, {},  'clear empties a registered hash in place' );
is_deeply( \@test_array, [], 'clear empties a registered array in place' );
is( $reset_ran, 1, 'clear runs a registered reset action' );

# LJ::start_request must route through clear(). This is the same call the web
# front door and the task worker loop (DW::TaskQueue) make to isolate one
# request/job from the next, so a value stashed by one must not survive into it.
DW::RequestCache->set( 'leak', 'k', 'from previous job' );
LJ::start_request();
ok( !DW::RequestCache->has( 'leak', 'k' ),
    'LJ::start_request clears the store (per-request/per-job isolation)' );

done_testing();
