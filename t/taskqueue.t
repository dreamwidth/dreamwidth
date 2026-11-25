# t/taskqueue.t
#
# Test DW::TaskQueue dispatch routing and DW::TaskQueue::LocalDisk send/receive
# lifecycle.
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

use Test::More tests => 31;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use File::Temp qw(tempdir);
use LJ::Test qw(with_fake_memcache);
use Log::Log4perl;
use Log::Log4perl::Appender::TestBuffer;

use DW::Task;
use DW::Task::SynSuck;
use DW::Task::DeleteEntry;
use DW::TaskQueue;
use DW::TaskQueue::LocalDisk;
use DW::TaskQueue::SQS;
use DW::TaskQueue::Dedup;

{

    package Local::PartialSQSSend;

    sub SendMessageBatch {
        my ( $self, %args ) = @_;
        die $self->{exception} if exists $self->{exception};
        my @ids = map { $_->{Id} } @{ $args{Entries} };
        push @{ $self->{requests} }, [ $args{QueueUrl}, @ids ];
        my $rejected = !$self->{accept_all} && $ids[0] eq 'id-0';
        return bless { failed => $rejected ? [ { Id => $ids[0] } ] : [] }, 'Local::SQSBatchResult';
    }
}

{

    package Local::SQSBatchResult;

    sub Failed { return $_[0]->{failed}; }
}

{

    package Local::SQSException;

    sub message { return 'simulated SQS service exception'; }
}

{
    no warnings 'redefine';
    local *DW::TaskQueue::SQS::_get_queue_for_task = sub { return ( ( ref $_[1] ) x 2 ); };

    my $sqs   = bless {}, 'Local::PartialSQSSend';
    my $queue = bless { sqs => $sqs }, 'DW::TaskQueue::SQS';
    my $task  = DW::Task::SynSuck->new( { userid => 42 } );

    subtest 'Single-task SQS send reports entry rejection' => sub {
        ok( !$queue->send($task), 'An unaccepted task must remain pending with the caller' );
        local $sqs->{accept_all} = 1;
        ok( $queue->send($task), 'An accepted task can be checkpointed' );
    };

    subtest 'A mixed SQS response does not abort or replay a bulk send' => sub {
        $sqs->{requests} = [];
        ok( $queue->send( ($task) x 11 ), 'Bulk caller does not retry already accepted entries' );
        is_deeply(
            $sqs->{requests},
            [ [ ref $task, map { "id-$_" } 0 .. 9 ], [ ref $task, 'id-10' ] ],
            'Later chunk is attempted and no chunk is replayed'
        );
    };

    subtest 'A rejected task does not stop dispatch to other task types' => sub {
        $sqs->{requests} = [];
        my $other = DW::Task::DeleteEntry->new( { uid => 2 } );
        ok( !DW::TaskQueue::dispatch( $queue, $task, $other ), 'Dispatch still reports failure' );
        is_deeply(
            [ sort map { $_->[0] } @{ $sqs->{requests} } ],
            [ sort ( ref $task, ref $other ) ],
            'Both queues are attempted regardless of dispatch order'
        );
    };

    subtest 'SQS send logs request-level exceptions' => sub {
        my $log_config = q{
log4perl.rootLogger=OFF
log4perl.logger.DW.TaskQueue.SQS=ERROR, Capture
log4perl.appender.Capture=Log::Log4perl::Appender::TestBuffer
log4perl.appender.Capture.layout=Log::Log4perl::Layout::PatternLayout
log4perl.appender.Capture.layout.ConversionPattern=%m%n
};
        Log::Log4perl::init( \$log_config );
        my $logs = Log::Log4perl::Appender::TestBuffer->by_name('Capture');
        local $sqs->{exception} = "simulated SQS transport failure\n";
        ok( !$queue->send($task), 'A thrown string reports request failure' );
        like( $logs->buffer, qr/simulated SQS transport failure/, 'String exception is logged' );

        $logs->buffer('');
        $sqs->{exception} = bless {}, 'Local::SQSException';
        ok( !$queue->send($task), 'A thrown object reports request failure' );
        like( $logs->buffer, qr/simulated SQS service exception/, 'Exception message is logged' );
    };
}

# --- Helper: create a LocalDisk instance pointed at a temp dir ---

sub fresh_localdisk {
    my $dir = tempdir( CLEANUP => 1 );
    my $q   = bless { path => $dir, queues => {} }, 'DW::TaskQueue::LocalDisk';
    return $q;
}

# --- LocalDisk send/receive round-trip (Storable mode) ---

{
    local $LJ::TASK_QUEUE_JSON = 0;
    my $q = fresh_localdisk();

    my $task = DW::Task::SynSuck->new( { userid => 42 } );
    my $rv   = $q->send($task);
    is( $rv, 1, 'LocalDisk send returns 1 on success' );

    my $messages = $q->receive( 'DW::Task::SynSuck', 10, 0 );
    is( ref $messages,     'ARRAY', 'receive returns arrayref' );
    is( scalar @$messages, 1,       'receive returns 1 message' );

    my ( $handle, $received_task ) = @{ $messages->[0] };
    ok( defined $handle, 'received message has a handle' );
    isa_ok( $received_task, 'DW::Task::SynSuck', 'received task class' );
    is_deeply( $received_task->args, [ { userid => 42 } ], 'received task args' );

    # completed removes the file
    $q->completed( 'DW::Task::SynSuck', $handle );
    my $after = $q->receive( 'DW::Task::SynSuck', 10, 0 );
    is( scalar @{ $after || [] }, 0, 'queue empty after completed' );
}

# --- LocalDisk send/receive round-trip (JSON mode) ---

{
    local $LJ::TASK_QUEUE_JSON = 1;
    my $q = fresh_localdisk();

    my $task = DW::Task::SynSuck->new( { userid => 99 } )
        ->with_dedup( uniqkey => 'test:99', dedup_ttl => 600 );
    $q->send($task);

    my $messages = $q->receive( 'DW::Task::SynSuck', 10, 0 );
    my ( $handle, $received_task ) = @{ $messages->[0] };
    isa_ok( $received_task, 'DW::Task::SynSuck', 'JSON mode: received task class' );
    is_deeply( $received_task->args, [ { userid => 99 } ], 'JSON mode: received task args' );
    is( $received_task->uniqkey,   'test:99', 'JSON mode: uniqkey survives round-trip' );
    is( $received_task->dedup_ttl, 600,       'JSON mode: dedup_ttl survives round-trip' );

    $q->completed( 'DW::Task::SynSuck', $handle );
}

# --- LocalDisk batch send ---

{
    local $LJ::TASK_QUEUE_JSON = 1;
    my $q = fresh_localdisk();

    my @tasks = map { DW::Task::SynSuck->new( { userid => $_ } ) } ( 1 .. 5 );
    my $rv    = $q->send(@tasks);
    is( $rv, 1, 'batch send returns 1' );

    my $messages = $q->receive( 'DW::Task::SynSuck', 10, 0 );
    is( scalar @$messages, 5, 'batch send: all 5 messages received' );

    # Complete them all
    my @handles = map { $_->[0] } @$messages;
    $q->completed( 'DW::Task::SynSuck', @handles );
    my $after = $q->receive( 'DW::Task::SynSuck', 10, 0 );
    is( scalar @{ $after || [] }, 0, 'batch send: queue empty after completing all' );
}

# --- LocalDisk: different task types get different queues ---

{
    local $LJ::TASK_QUEUE_JSON = 1;
    my $q = fresh_localdisk();

    $q->send( DW::Task::SynSuck->new(     { userid => 1 } ) );
    $q->send( DW::Task::DeleteEntry->new( { uid    => 2 } ) );

    my $syn_msgs = $q->receive( 'DW::Task::SynSuck', 10, 0 );
    is( scalar @$syn_msgs, 1, 'SynSuck queue has 1 message' );
    isa_ok( $syn_msgs->[0][1], 'DW::Task::SynSuck', 'SynSuck queue has correct type' );

    my $del_msgs = $q->receive( 'DW::Task::DeleteEntry', 10, 0 );
    is( scalar @$del_msgs, 1, 'DeleteEntry queue has 1 message' );
    isa_ok( $del_msgs->[0][1], 'DW::Task::DeleteEntry', 'DeleteEntry queue has correct type' );
}

# --- LocalDisk: empty receive returns empty ---

{
    my $q    = fresh_localdisk();
    my $msgs = $q->receive( 'DW::Task::SynSuck', 10, 0 );
    is( scalar @{ $msgs || [] }, 0, 'receive on empty queue returns empty' );
}

# --- DW::TaskQueue dispatch with dedup gating ---

with_fake_memcache {
    local $LJ::TASK_QUEUE_JSON = 1;

    # Mock DW::TaskQueue to use a fresh LocalDisk
    my $q = fresh_localdisk();

    # First dispatch should succeed
    my $task1 = DW::Task::SynSuck->new( { userid => 42 } )
        ->with_dedup( uniqkey => 'synsuck:42', dedup_ttl => 60 );
    my $rv = $q->send($task1);

    # Simulate dispatch dedup check
    my $claimed = DW::TaskQueue::Dedup->claim_unique( 'DW::Task::SynSuck', 'synsuck:42', 60 );
    is( $claimed, 1, 'dispatch: first dedup claim succeeds' );

    # Second dispatch with same key should be blocked
    my $claimed2 = DW::TaskQueue::Dedup->claim_unique( 'DW::Task::SynSuck', 'synsuck:42', 60 );
    is( $claimed2, 0, 'dispatch: duplicate dedup claim blocked' );

    # After release, can claim again
    DW::TaskQueue::Dedup->release_unique( 'DW::Task::SynSuck', 'synsuck:42' );
    my $claimed3 = DW::TaskQueue::Dedup->claim_unique( 'DW::Task::SynSuck', 'synsuck:42', 60 );
    is( $claimed3, 1, 'dispatch: dedup claim succeeds after release' );
};

# --- DW::Task queue_attributes ---

{
    my $task  = DW::Task::SynSuck->new( { userid => 1 } );
    my %attrs = $task->queue_attributes;
    is( $attrs{VisibilityTimeout},             300,     'queue_attributes: VisibilityTimeout' );
    is( $attrs{ReceiveMessageWaitTimeSeconds}, 10,      'queue_attributes: WaitTimeSeconds' );
    is( $attrs{MessageRetentionPeriod},        345_600, 'queue_attributes: RetentionPeriod' );
}

{
    local $LJ::SQS{region}  = 'us-east-1';
    local $LJ::SQS{account} = 123456789012;
    my $task  = DW::Task::SynSuck->new( { userid => 1 } );
    my %attrs = $task->queue_attributes( dlq => 'dw-prod-dw-task-synsuck-dlq' );
    ok( exists $attrs{RedrivePolicy}, 'queue_attributes: RedrivePolicy present with dlq' );
    like(
        $attrs{RedrivePolicy},
        qr/arn:aws:sqs:us-east-1:123456789012:dw-prod-dw-task-synsuck-dlq/,
        'queue_attributes: RedrivePolicy contains correct DLQ ARN'
    );
}
