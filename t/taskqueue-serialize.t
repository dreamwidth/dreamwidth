# t/taskqueue-serialize.t
#
# Test DW::Task serialize/deserialize (v2 JSON wire format).
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

use Test::More tests => 26;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use MIME::Base64 qw(encode_base64);
use Storable qw(nfreeze);

use DW::Task;
use DW::Task::SynSuck;
use DW::Task::DeleteEntry;

# --- Default mode (flag off): serialize produces Storable format ---

{
    local $LJ::TASK_QUEUE_JSON = 0;
    my $task = DW::Task::SynSuck->new( { userid => 42 } );
    my $body = $task->serialize();
    unlike( $body, qr/^v2:json:/, 'flag off: serialize produces Storable format' );

    my $restored = DW::Task->deserialize($body);
    isa_ok( $restored, 'DW::Task::SynSuck', 'flag off: Storable round-trip class' );
    is_deeply( $restored->args, [ { userid => 42 } ], 'flag off: Storable round-trip args' );
}

# --- JSON mode (flag on): serialize produces v2:json format ---

{
    local $LJ::TASK_QUEUE_JSON = 1;
    my $task = DW::Task::SynSuck->new( { userid => 42 } );
    my $body = $task->serialize();
    like( $body, qr/^v2:json:/, 'flag on: serialize produces v2:json: prefix' );
    like(
        $body,
        qr/"class"\s*:\s*"DW::Task::SynSuck"/,
        'flag on: serialized body contains class name'
    );

    my $restored = DW::Task->deserialize($body);
    isa_ok( $restored, 'DW::Task::SynSuck', 'flag on: deserialized v2 task isa correct class' );
    is_deeply(
        $restored->args,
        [ { userid => 42 } ],
        'flag on: deserialized v2 task has correct args'
    );
    is( $restored->uniqkey,   undef, 'flag on: deserialized v2 task uniqkey undef when not set' );
    is( $restored->dedup_ttl, undef, 'flag on: deserialized v2 task dedup_ttl undef when not set' );
}

# --- JSON mode: round-trip with dedup fields ---

{
    local $LJ::TASK_QUEUE_JSON = 1;
    my $task = DW::Task::SynSuck->new( { userid => 99 } )
        ->with_dedup( uniqkey => 'synsuck:99', dedup_ttl => 1800 );
    my $body     = $task->serialize();
    my $restored = DW::Task->deserialize($body);
    isa_ok( $restored, 'DW::Task::SynSuck', 'v2 dedup task isa correct class' );
    is_deeply( $restored->args, [ { userid => 99 } ], 'v2 dedup task args correct' );
    is( $restored->uniqkey,   'synsuck:99', 'v2 dedup task uniqkey survives round-trip' );
    is( $restored->dedup_ttl, 1800,         'v2 dedup task dedup_ttl survives round-trip' );
}

# --- Percentage rollout ---

{
    local $LJ::TASK_QUEUE_JSON = 1.0;
    my $json_count = 0;
    for ( 1 .. 200 ) {
        my $task = DW::Task::SynSuck->new( { userid => $_ } );
        my $body = $task->serialize();
        $json_count++ if $body =~ /^v2:json:/;
    }
    is( $json_count, 200, 'flag=1.0: all 200 messages are JSON' );

    local $LJ::TASK_QUEUE_JSON = 0.0;
    $json_count = 0;
    for ( 1 .. 200 ) {
        my $task = DW::Task::SynSuck->new( { userid => $_ } );
        my $body = $task->serialize();
        $json_count++ if $body =~ /^v2:json:/;
    }
    is( $json_count, 0, 'flag=0.0: all 200 messages are Storable' );
}

# --- JSON mode: falls back to Storable on non-JSON-safe args ---

{
    local $LJ::TASK_QUEUE_JSON = 1;

    my $blessed_arg = bless { x => 1 }, 'Some::Thing';
    my $task        = DW::Task::SynSuck->new($blessed_arg);
    my $body        = $task->serialize();
    unlike( $body, qr/^v2:json:/, 'JSON fallback: non-JSON-safe args produce Storable' );

    my $restored = DW::Task->deserialize($body);
    isa_ok( $restored, 'DW::Task::SynSuck', 'JSON fallback: Storable round-trip class' );
}

# --- Legacy Storable format still deserializes correctly ---

{
    my $task = DW::Task::SynSuck->new( { userid => 7 } )
        ->with_dedup( uniqkey => 'synsuck:7', dedup_ttl => 900 );
    my $legacy_body = encode_base64( nfreeze($task) );
    my $restored    = DW::Task->deserialize($legacy_body);
    isa_ok( $restored, 'DW::Task::SynSuck', 'legacy Storable task isa correct class' );
    is_deeply( $restored->args, [ { userid => 7 } ], 'legacy Storable task args correct' );
    is( $restored->uniqkey,   'synsuck:7', 'legacy Storable task uniqkey correct' );
    is( $restored->dedup_ttl, 900,         'legacy Storable task dedup_ttl correct' );
}

# --- Class name validation ---

{
    eval { DW::Task->deserialize('v2:json:{"class":"Evil::Class","args":[]}') };
    like( $@, qr/Invalid task class/, 'rejects non-DW::Task class' );

    eval { DW::Task->deserialize('v2:json:{"class":"DW::Task","args":[]}') };
    like( $@, qr/Invalid task class/, 'rejects DW::Task base class (requires subclass)' );

    eval { DW::Task->deserialize('v2:json:{"class":"DW::Task::../../etc/passwd","args":[]}') };
    like( $@, qr/Invalid task class/, 'rejects path traversal in class name' );
}

# --- Multiple task types round-trip correctly ---

{
    local $LJ::TASK_QUEUE_JSON = 1;
    my $task     = DW::Task::DeleteEntry->new( { uid => 1, jitemid => 2, anum => 3 } );
    my $restored = DW::Task->deserialize( $task->serialize() );
    isa_ok( $restored, 'DW::Task::DeleteEntry', 'DeleteEntry v2 round-trip class' );
    is_deeply(
        $restored->args,
        [ { uid => 1, jitemid => 2, anum => 3 } ],
        'DeleteEntry v2 round-trip args'
    );
}
