# t/taskqueue-dedup.t
#
# Test DW::Task construction, dedup fields, and DW::TaskQueue::Dedup logic.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More tests => 39;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(with_fake_memcache);
use Storable qw(freeze thaw);

use DW::Task;
use DW::Task::SynSuck;
use DW::Task::DeleteEntry;
use DW::Task::LatestFeed;
use DW::Task::MassPrivacy;
use DW::TaskQueue::Dedup;

# --- DW::Task base class ---

{
    my $task = DW::Task->new( { foo => 1 } );
    isa_ok( $task, 'DW::Task', 'base task isa DW::Task' );
    is_deeply( $task->args, [ { foo => 1 } ], 'args accessor returns constructor args' );
    is( $task->uniqkey,          undef, 'uniqkey is undef by default' );
    is( $task->dedup_ttl,        undef, 'dedup_ttl is undef by default' );
    is( $task->receive_count,    0,     'receive_count defaults to 0' );
    is( $task->receive_count(3), 3,     'receive_count setter returns new value' );
    is( $task->receive_count,    3,     'receive_count getter returns set value' );
}

# --- with_dedup on base class ---

{
    my $task = DW::Task->new( { x => 1 } )->with_dedup( uniqkey => 'test:1', dedup_ttl => 600 );
    isa_ok( $task, 'DW::Task', 'with_dedup returns a DW::Task' );
    is_deeply( $task->args, [ { x => 1 } ], 'args unaffected by with_dedup' );
    is( $task->uniqkey,   'test:1', 'uniqkey set via with_dedup' );
    is( $task->dedup_ttl, 600,      'dedup_ttl set via with_dedup' );
}

# --- DW::Task::SynSuck construction ---

{
    my $task = DW::Task::SynSuck->new( { userid => 42 } );
    isa_ok( $task, 'DW::Task::SynSuck', 'SynSuck isa SynSuck' );
    isa_ok( $task, 'DW::Task',          'SynSuck isa DW::Task' );
    is_deeply( $task->args, [ { userid => 42 } ], 'SynSuck args without dedup' );
    is( $task->uniqkey,   undef, 'SynSuck uniqkey undef without dedup' );
    is( $task->dedup_ttl, undef, 'SynSuck dedup_ttl undef without dedup' );
}

{
    my $task = DW::Task::SynSuck->new( { userid => 99 } )
        ->with_dedup( uniqkey => 'synsuck:99', dedup_ttl => 1800 );
    is_deeply( $task->args, [ { userid => 99 } ], 'SynSuck args with dedup' );
    is( $task->uniqkey,   'synsuck:99', 'SynSuck uniqkey set via with_dedup' );
    is( $task->dedup_ttl, 1800,         'SynSuck dedup_ttl set via with_dedup' );
}

# --- Storable round-trip ---

{
    my $task = DW::Task::SynSuck->new( { userid => 7 } )
        ->with_dedup( uniqkey => 'synsuck:7', dedup_ttl => 900 );
    my $frozen = freeze($task);
    my $thawed = thaw($frozen);
    isa_ok( $thawed, 'DW::Task::SynSuck', 'thawed task isa SynSuck' );
    is_deeply( $thawed->args, [ { userid => 7 } ], 'args survive freeze/thaw' );
    is( $thawed->uniqkey,   'synsuck:7', 'uniqkey survives freeze/thaw' );
    is( $thawed->dedup_ttl, 900,         'dedup_ttl survives freeze/thaw' );
}

# --- receive_count (set by SQS layer post-thaw) ---

{
    my $task = DW::Task::SynSuck->new( { userid => 10 } );
    is( $task->receive_count, 0, 'receive_count defaults to 0 on subclass' );

    $task->receive_count(5);
    is( $task->receive_count, 5, 'receive_count works on subclass' );

    # In production, receive_count is never set before freeze — tasks are
    # serialized at send time (no count yet) and the count is set by the
    # SQS layer after thaw. Verify that flow works.
    my $fresh  = DW::Task::SynSuck->new( { userid => 11 } );
    my $thawed = thaw( freeze($fresh) );
    is( $thawed->receive_count, 0, 'thawed task has receive_count 0' );

    $thawed->receive_count(3);
    is( $thawed->receive_count, 3, 'receive_count can be set after thaw' );
}

# --- Other task subclass construction ---

{
    my $task = DW::Task::DeleteEntry->new( { uid => 1, jitemid => 2, anum => 3 } );
    isa_ok( $task, 'DW::Task::DeleteEntry', 'DeleteEntry construction' );
    is_deeply( $task->args, [ { uid => 1, jitemid => 2, anum => 3 } ], 'DeleteEntry args' );
}

{
    my $task = DW::Task::LatestFeed->new( { action => 'add' } );
    isa_ok( $task, 'DW::Task::LatestFeed', 'LatestFeed construction' );
    is_deeply( $task->args, [ { action => 'add' } ], 'LatestFeed args' );
}

{
    my $task = DW::Task::MassPrivacy->new( { userid => 5, security => 'private' } );
    isa_ok( $task, 'DW::Task::MassPrivacy', 'MassPrivacy construction' );
    is_deeply( $task->args, [ { userid => 5, security => 'private' } ], 'MassPrivacy args' );
}

# --- DW::TaskQueue::Dedup ---

with_fake_memcache {

    # claim_unique
    my $rv = DW::TaskQueue::Dedup->claim_unique( 'TestQueue', 'key1', 60 );
    is( $rv, 1, 'claim_unique succeeds on first call' );

    my $rv2 = DW::TaskQueue::Dedup->claim_unique( 'TestQueue', 'key1', 60 );
    is( $rv2, 0, 'claim_unique returns 0 for duplicate' );

    # is_pending
    is( DW::TaskQueue::Dedup->is_pending( 'TestQueue', 'key1' ),
        1, 'is_pending returns 1 when claimed' );
    is( DW::TaskQueue::Dedup->is_pending( 'TestQueue', 'key_nonexistent' ),
        0, 'is_pending returns 0 for unclaimed key' );

    # release_unique
    DW::TaskQueue::Dedup->release_unique( 'TestQueue', 'key1' );
    is( DW::TaskQueue::Dedup->is_pending( 'TestQueue', 'key1' ),
        0, 'is_pending returns 0 after release' );

    my $rv3 = DW::TaskQueue::Dedup->claim_unique( 'TestQueue', 'key1', 60 );
    is( $rv3, 1, 'claim_unique succeeds after release' );
};
