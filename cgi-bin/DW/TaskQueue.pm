#!/usr/bin/perl
#
# DW::TaskQueue
#
# Library for queueing and executing jobs.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2019 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::TaskQueue;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

# use Coro;
use MIME::Base64;
use Paws;
use Paws::Credential::InstanceProfile;
use Storable qw/ nfreeze thaw /;
use Time::HiRes qw/ time /;
use UUID::Tiny qw/ :std /;

use DW::Task;

use constant LARGE_MESSAGE_CUTOFF => 255_000;
use constant MAX_BATCH_SIZE       => 10;

my $_queue;

sub get {
    my $class = $_[0];
    return $_queue //= $class->init(%LJ::SQS);
}

sub init {
    my ( $class, %args ) = @_;

    foreach my $required (qw/ region prefix /) {
        $log->logcroak( 'SQS configuration must include config: ', $required )
            unless exists $args{$required};
    }

    $log->logcroak('Prefix does not match required regex: [a-zA-Z0-9_-]+$.')
        if defined $args{prefix} && $args{prefix} !~ /^[a-zA-Z0-9_-]+$/;

    my $credentials = Paws::Credential::InstanceProfile->new;
    if ( defined $args{access_key} && defined $args{secret_key} ) {
        $log->warn('Using INSECURE AWS configuration!');
        $credentials = Paws::Credential::Local->new(
            access_key => $args{access_key},
            secret_key => $args{secret_key},
        );
    }

    my $paws = Paws->new(
        config => {
            credentials => $credentials,
            region      => $args{region},
        },
    ) or $log->logcroak('Failed to initialize Paws object.');
    my $sqs = $paws->service('SQS')
        or $log->logcroak('Failed to initialize Paws::SQS object.');

    $log->debug("Initializing taskqueue for SQS");
    my $self = {
        sqs    => $sqs,
        prefix => $args{prefix},
        queues => {},
    };
    return bless $self, $class;
}

sub _get_queue_for_task {
    my ( $self, $task ) = @_;

    my $queue_name = lc( ref $task || $task );
    $queue_name =~ s/::/-/g;
    $queue_name = $self->{prefix} . $queue_name;

    return ( $queue_name, $self->{queues}->{$queue_name} )
        if exists $self->{queues}->{$queue_name};

    my $res = eval { $self->{sqs}->GetQueueUrl( QueueName => $queue_name ) };
    if ( $@ && $@->isa('Paws::Exception') ) {
        $log->warn("Failed to get queue $queue_name, creating.");

        $res = eval {
            $self->{sqs}
                ->CreateQueue( QueueName => $queue_name, Attributes => $task->queue_attributes );
        };
        if ( $@ && $@->isa('Paws::Exception') ) {
            $log->error( "Failed to create queue $queue_name: " . $@->message );
            return;
        }

        $res = eval { $self->{sqs}->GetQueueUrl( QueueName => $queue_name ) };
        if ( $@ && $@->isa('Paws::Exception') ) {
            $log->error( "Failed to get queue $queue_name after creating: " . $@->message );
            return;
        }
    }

    return ( $queue_name, $self->{queues}->{$queue_name} = $res->QueueUrl );
}

sub dispatch {
    my ( $self, @tasks ) = @_;
    return undef unless @tasks;

    $self = $self->get unless ref $self;

    # This is a shim function that inspects the tasks being sent and dispatches
    # them to the appropriate task queueing system.
    my ( @schwartz_jobs, @sqs_tasks );
    foreach my $task (@tasks) {
        if ( $task->isa('TheSchwartz::Job') ) {
            push @schwartz_jobs, $task;
        }
        elsif ( $task->isa('DW::Task') ) {
            push @sqs_tasks, $task;
        }
        elsif ( $task->isa('LJ::Event') ) {

            # Do the SQS check, because these tasks could go either way, and we
            # want to be able to ramp up the traffic slowly.
            if ( $LJ::ESN_OVER_SQS && rand() < $LJ::ESN_OVER_SQS ) {
                push @sqs_tasks, $task->fire_task;
            }
            else {
                push @schwartz_jobs, $task->fire_job;
            }
        }
        else {
            $log->error( 'Unknown job/task type, dropping: ' . ref($task) );
        }
    }

    my $rv = 1;

    # Dispatch to Schwartz
    if (@schwartz_jobs) {
        if ( my $sclient = LJ::theschwartz() ) {
            $log->debug( 'Inserting ' . scalar(@schwartz_jobs) . ' jobs into TheSchwartz.' );
            $rv &&= $sclient->insert_jobs(@schwartz_jobs);
        }
        else {
            $log->warn( 'Failed to retrieve TheSchwartz client, dropping '
                    . scalar(@schwartz_jobs)
                    . ' jobs.' );
        }
    }

    # Dispatch to SQS
    if (@sqs_tasks) {
        $log->debug( 'Inserting ' . scalar(@sqs_tasks) . ' tasks into SQS.' );
        $rv &&= $self->send(@sqs_tasks);
    }

    # Returns the "worse" of the return values. If either are falsey, we will
    # return a false value.
    return $rv;
}

# Send a group of tasks to SQS. Returns 1 if all succeeded or undef if there was one
# or more failures. TODO: might be nice to make it so callers can determine which messages
# succeeded, maybe?
sub send {
    my ( $self, @tasks ) = @_;
    return undef unless @tasks;

    $self = $self->get unless ref $self;

    my ( $queue_name, $queue_url ) = $self->_get_queue_for_task( $tasks[0] )
        or return undef;

    my $tags = [ 'queue:' . $queue_name ];
    DW::Stats::increment( 'dw.taskqueue.action.send_attempt', scalar(@tasks), $tags );

    # Send batches of messages, limited by count or size
    my @messages;
    my ( $sent_bytes, $ctr ) = ( 0, 0 );

    my $send = sub {
        $log->debug( 'Sending ', scalar(@messages), ' messages: ', $sent_bytes,
            ' bytes to queue: ', $queue_name );
        my $res =
            eval { $self->{sqs}->SendMessageBatch( QueueUrl => $queue_url, Entries => \@messages ) };
        if ( $@ && $@->isa('Paws::Exception') ) {
            $log->error( 'Failed to send SQS message batch: ', $@->message );
            DW::Stats::increment( 'dw.taskqueue.action.send_error', scalar(@messages), $tags );
            return undef;
        }
        else {
            $log->debug( 'Successfully sent ', scalar(@messages), ' messages.' );
            DW::Stats::increment( 'dw.taskqueue.action.send_ok', scalar(@messages), $tags );
            DW::Stats::increment( 'dw.taskqueue.sent_messages',  scalar(@tasks),    $tags );
        }

        @messages   = ();
        $sent_bytes = 0;
        return 1;
    };

    foreach my $task (@tasks) {
        my $body = $self->_offload_large_message_if_necessary($task);

        # If this message would put us over the cap, we need to send the previous batch
        # before appending it
        if (
            @messages
            && ( $sent_bytes + length $body > LARGE_MESSAGE_CUTOFF
                || scalar @messages == MAX_BATCH_SIZE )
            )
        {
            $send->() or return undef;
        }

        # Safe to append this messages
        $sent_bytes += length $body;
        push @messages, { Id => 'id-' . $ctr++, MessageBody => $body };
    }

    # If there are any messages left send them
    if (@messages) {
        $send->() or return undef;
    }

    # If any messages had failed, we would have early returned elsewhere when a
    # call to $send failed
    return 1;
}

sub _offload_large_message_if_necessary {
    my ( $self, $message ) = @_;

    $message = encode_base64( nfreeze($message) );
    return $message if length $message < LARGE_MESSAGE_CUTOFF;

    my $uuid = create_uuid_as_string(UUID_V4);
    my $rv   = DW::BlobStore->store( tasks => $uuid, \$message );
    unless ($rv) {
        $log->error('Failed to offload task to BlobStore!');
        DW::Stats::increment( 'dw.taskqueue.action.send_offload_error', 1 );
        return undef;
    }

    DW::Stats::increment( 'dw.taskqueue.action.send_offload_ok', 1 );
    return 'offloaded:' . $uuid;
}

sub _reload_large_message_if_necessary {
    my ( $self, $message ) = @_;

    my $uuid = $1
        if $message =~ /^offloaded:(.+?)$/;
    return $message unless $uuid;

    my $rv = DW::BlobStore->retrieve( tasks => $uuid );
    unless ($rv) {
        $log->error( 'Failed to reload task from BlobStore: ' . $uuid );
        DW::Stats::increment( 'dw.taskqueue.action.send_reload_error', 1 );
        return undef;
    }

    DW::Stats::increment( 'dw.taskqueue.action.send_reload_ok', 1 );
    return $$rv;
}

sub receive {
    my ( $self, $class, $count ) = @_;
    $count ||= 10;

    $self = $self->get unless ref $self;

    my ( $queue_name, $queue_url ) = $self->_get_queue_for_task($class)
        or return undef;

    my $tags = [ 'queue:' . $queue_name ];
    DW::Stats::increment( 'dw.taskqueue.action.receive_attempt', 1, $tags );

    my $res = eval {
        $self->{sqs}->ReceiveMessage(
            QueueUrl            => $queue_url,
            MaxNumberOfMessages => $count,
            WaitTimeSeconds     => 10
        );
    };
    if ( $@ && $@->isa('Paws::Exception') ) {
        $log->warn( 'Failed to retrieve SQS messages: ' . $@->message );
        DW::Stats::increment( 'dw.taskqueue.action.receive_error', 1, $tags );
        return undef;
    }

    my $messages = $res->Messages;
    unless ( $messages && ref $messages eq 'ARRAY' && length @$messages >= 1 ) {
        DW::Stats::increment( 'dw.taskqueue.action.receive_empty', 1, $tags );
        return undef;
    }

    DW::Stats::increment( 'dw.taskqueue.action.receive_ok', 1, $tags );
    DW::Stats::increment( 'dw.taskqueue.received_messages', scalar(@$messages), $tags );
    $messages = [
        map {
            [
                $_->ReceiptHandle,
                thaw( decode_base64( $self->_reload_large_message_if_necessary( $_->Body ) ) )
            ]
        } @$messages
    ];
    return $messages;
}

sub completed {
    my ( $self, $class, @handles ) = @_;
    return unless @handles;

    $self = $self->get unless ref $self;

    my ( $queue_name, $queue_url ) = $self->_get_queue_for_task($class)
        or return undef;

    my $tags = [ 'queue:' . $queue_name ];
    DW::Stats::increment( 'dw.taskqueue.action.completed_attempt', 1, $tags );

    my $res = eval {
        my $idx = 0;
        $self->{sqs}->DeleteMessageBatch(
            QueueUrl => $queue_url,
            Entries  => [ map { { Id => $idx++, ReceiptHandle => $_ } } @handles ]
        );
    };
    if ( $@ && $@->isa('Paws::Exception') ) {
        $log->warn( 'Failed to delete message batch: ', $@->message );
        DW::Stats::increment( 'dw.taskqueue.action.completed_error', 1, $tags );
        return undef;
    }

    # TODO: We could return information about which messages failed to complete,
    # and then do something else with them, but not sure what to do yet.
    DW::Stats::increment( 'dw.taskqueue.action.completed_ok', 1, $tags );
    DW::Stats::increment( 'dw.taskqueue.completed_messages', scalar(@handles), $tags );
}

sub start_work {
    my ( $self, $class ) = @_;

    $self = $self->get unless ref $self;

    eval "use $class;";

    my $start_time = time();

    # Turn on coroutines for MySQL so that our database handles will
    # activate the scheduler for us
    # $LJ::ENABLE_CORO_MYSQL = 1;

    while (1) {
        my $recv_start_time = time();
        my $messages        = $self->receive( $class, 10 );
        my $recv_time       = time() - $recv_start_time;

        unless (@$messages) {
            $log->debug( sprintf( '[%s %0.3fs] Receive finished, empty', $class, $recv_time ) );
            next;
        }

        $log->debug(
            sprintf(
                '[%s %0.3fs] Receive finished, %d messages',
                $class, $recv_time, scalar(@$messages)
            )
        );

        my ( @completed, @failed );
        my ( $work_start_time, $work_end_time, @coros );
        foreach my $message_pair (@$messages) {
            my ( $handle, $message ) = @$message_pair;

            #push @coros, async {

            # Record earliest start time of any coroutine
            my $local_start_time = time();
            $work_start_time = $local_start_time
                if $local_start_time < $work_start_time || !defined $work_start_time;

            my $res = $message->work($handle);

            # Record latest end time of any coroutine
            my $local_end_time = time();
            $work_end_time = $local_end_time
                if $local_end_time > $work_end_time || !defined $work_end_time;

            if ( $res == DW::Task::COMPLETED ) {
                push @completed, $handle;
            }
            else {
                $log->warn( sprintf( '[%s] Message "%s" failed', $class, $handle ) );
                push @failed, $handle;
            }

            #};
        }

        # Wait for all coroutines to have finished and exited
        #$_->join foreach @coros;

        $log->debug(
            sprintf(
                '[%s %0.3fs] Processed %d messages (%d failed)',
                $class, $work_end_time - $work_start_time,
                scalar(@$messages), scalar(@failed)
            )
        );
        next unless @completed;

        my $complete_start_time = time();
        $self->completed( $class, @completed );
        my $complete_time = time() - $complete_start_time;

        $log->debug(
            sprintf(
                '[%s %0.3fs] Marked %d messages complete',
                $class, $complete_time, scalar(@completed)
            )
        );
    }
}

sub _queue_name_from_url {
    my $queue_url = $_[0];
    return $1 if $queue_url =~ m|/([^/]+)$|;
    return;
}

sub queue_attributes {
    my ( $self, $queue ) = @_;

    my @queues;
    if ($queue) {
        my ( $_queue_name, $queue_url ) = $self->_get_queue_for_task($queue);
        unless ($queue_url) {
            $log->error( 'Failed to fetch URL for queue: ', $queue );
            return;
        }
        push @queues, $queue_url;
    }
    else {
        my $res = eval { $self->{sqs}->ListQueues( QueueNamePrefix => $self->{prefix}, ) };
        if ( $@ && $@->isa('Paws::Exception') ) {
            $log->warn( 'Failed to list queues: ', $@->message );
            return;
        }

        @queues = @{ $res->QueueUrls || [] };
    }

    return {} unless @queues;

    my $rv = {};
    foreach my $queue_url (@queues) {
        my $res = eval {
            $self->{sqs}->GetQueueAttributes(
                QueueUrl       => $queue_url,
                AttributeNames => ['ApproximateNumberOfMessages']
            );
        };
        if ( $@ && $@->isa('Paws::Exception') ) {
            $log->warn( 'Failed to get queue attributes for ', $queue_url, ': ', $@->message );
            next;
        }

        $rv->{ _queue_name_from_url($queue_url) } = $res->Attributes;
    }
    return $rv;
}

################################################################################
#
# Paws::Credential::Local
#
# Implements the Paws::Credential role for passing in the access credentials
# directly. You would think this would be a default package supplied
# by the library...
#

package Paws::Credential::Local;

use Moose;

has access_key    => ( is => 'ro' );
has secret_key    => ( is => 'ro' );
has session_token => ( is => 'ro', default => sub { undef } );

with 'Paws::Credential';

no Moose;

1;
