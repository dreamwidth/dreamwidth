# t/cache.t
#
# Tests for DW::Cache: the per-scope KV memoization API, the registration API,
# scope independence, and the clear() guarantee that LJ::start_request (request
# scope) and LJ::handle_caches (process scope) rely on.
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
use DW::Cache;

my $req  = DW::Cache->request;
my $proc = DW::Cache->process;

is( $req->name,         'request', 'request scope knows its name' );
is( $proc->name,        'process', 'process scope knows its name' );
is( DW::Cache->request, $req,      'request scope is a singleton' );

# ---- KV store API ----

$req->set( 'ns', 'k', 'v' );
is( $req->get( 'ns', 'k' ), 'v', 'get returns the set value' );
ok( $req->has( 'ns', 'k' ), 'has is true for a present key' );
ok( !$req->has( 'ns', 'x' ), 'has is false for an absent key' );
is( $req->get( 'ns', 'x' ), undef, 'get is undef for an absent key' );

# a read miss must not autovivify the namespace (would inflate memory silently)
$req->get( 'never', 'k' );
ok( !exists $req->{store}{never}, 'get does not autovivify the namespace' );

# memoize computes once and caches, including a false result
my $calls = 0;
my $code  = sub { $calls++; return 0 };
is( $req->memoize( 'm', 'k', $code ), 0, 'memoize returns the computed value' );
is( $req->memoize( 'm', 'k', $code ), 0, 'memoize returns the cached value' );
is( $calls, 1, 'memoize computes exactly once, caching even a false value' );

# remove and clear_ns
$req->set( 'ns', 'k2', 'v2' );
$req->remove( 'ns', 'k' );
ok( !$req->has( 'ns', 'k' ), 'remove drops the target key' );
ok( $req->has( 'ns', 'k2' ), 'remove leaves sibling keys' );
$req->clear_ns('ns');
ok( !$req->has( 'ns', 'k2' ), 'clear_ns drops the whole namespace' );

# ---- scope independence ----

$req->set( 'shared_ns', 'k', 'request value' );
$proc->set( 'shared_ns', 'k', 'process value' );
is( $req->get( 'shared_ns', 'k' ), 'request value', 'scopes do not share a store' );

$req->clear;
is(
    $proc->get( 'shared_ns', 'k' ),
    'process value',
    'clearing request scope leaves process scope intact'
);
$proc->clear_ns('shared_ns');

# ---- registration API ----

my %test_hash  = ( a => 1 );
my @test_array = ( 1, 2, 3 );
my $reset_ran  = 0;
$req->register_var( 't_hash',  \%test_hash );
$req->register_var( 't_array', \@test_array );
$req->register_reset( 't_reset', sub { $reset_ran++ } );

# ---- the guarantee: clear() empties everything routed through the scope ----

$req->set( 'm2', 'survives', 'until clear' );
$req->clear;

ok( !$req->has( 'm2', 'survives' ), 'clear empties the KV store' );
is_deeply( \%test_hash, {},  'clear empties a registered hash in place' );
is_deeply( \@test_array, [], 'clear empties a registered array in place' );
is( $reset_ran, 1, 'clear runs a registered reset action' );

# ---- sizing stays in lockstep with clearing ----

$req->set( 'sized_ns', 'k', 'v' );
my %measurable = map { $_->{name} => 1 } $req->_measurable;
ok( $measurable{sized_ns}, 'a KV namespace is measurable' );
ok( $measurable{t_hash},   'a registered var is measurable' );
ok( !$measurable{t_reset}, 'a register_reset entry is not measurable (nothing to size)' );
$req->clear;

# ---- lifecycle integration ----

# LJ::start_request must clear the request scope. This is the same call the web
# front door and the task worker loop (DW::TaskQueue) make to isolate one
# request/job from the next, so a value stashed by one must not survive into it.
$req->set( 'leak', 'k', 'from previous job' );
$proc->set( 'longlived', 'k', 'reference data' );
LJ::start_request();
ok( !$req->has( 'leak', 'k' ),
    'LJ::start_request clears the request scope (per-request/per-job isolation)' );
is(
    $proc->get( 'longlived', 'k' ),
    'reference data',
    'LJ::start_request leaves the process scope alone'
);

# LJ::handle_caches must clear the process scope when $LJ::CLEAR_CACHES is set
# (the config-reload/HUP path).
{
    local $LJ::CLEAR_CACHES = 1;
    LJ::handle_caches();
}
ok( !$proc->has( 'longlived', 'k' ), 'LJ::handle_caches clears the process scope on CLEAR_CACHES' );

done_testing();
