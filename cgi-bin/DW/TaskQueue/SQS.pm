#!/usr/bin/perl
#
# DW::TaskQueue::SQS
#
# Library for queueing and executing jobs via Amazon SQS.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2019-2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::TaskQueue::SQS;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use MIME::Base64 qw/ encode_base64 decode_base64 /;
use Paws;
use Storable qw/ nfreeze thaw /;
use Time::HiRes qw/ time /;
use UUID::Tiny qw/ :std /;

use DW::Task;

use constant LARGE_MESSAGE_CUTOFF => 255_000;
use constant MAX_BATCH_SIZE       => 10;

sub init {
    my ( $class, %args ) = @_;

    foreach my $required (qw/ region prefix /) {
        $log->logcroak( 'SQS configuration must include config: ', $required )
            unless exists $args{$required};
    }

    $log->logcroak('Prefix does not match required regex: [a-zA-Z0-9_-]+$.')
        if defined $args{prefix} && $args{prefix} !~ /^[a-zA-Z0-9_-]+$/;

    my $paws = Paws->new(
        config => {
            region => $args{region},
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
    my ( $self, $task, %opts ) = @_;

    my ( $dlq_name, $dlq_url );
    my $queue_name = lc( ref $task || $task );
    unless ( $opts{dlq} ) {
        $queue_name =~ s/::/-/g;
        $queue_name = $self->{prefix} . $queue_name;

        $dlq_name = $queue_name . '-dlq';
        $dlq_url  = $self->_get_queue_for_task( $dlq_name, dlq => { $task->queue_attributes } );
    }

    # Cache hit?
    return ( $queue_name, $self->{queues}->{$queue_name} )
        if exists $self->{queues}->{$queue_name};

    # Fetch queue attributes
    my $queue_attrs = $opts{dlq} // { $task->queue_attributes( dlq => $dlq_name ) };

    # Fall back to SQS
    my $res = eval { $self->{sqs}->GetQueueUrl( QueueName => $queue_name ) };
    if ( $@ && $@->isa('Paws::Exception') ) {
        $log->warn("Failed to get queue $queue_name, creating.");

        # Fall back to creating the queue
        $res = eval {
            $self->{sqs}->CreateQueue(
                QueueName  => $queue_name,
                Attributes => $queue_attrs,
            );
        };
        if ( $@ && $@->isa('Paws::Exception') ) {
            $log->error( "Failed to create queue $queue_name: " . $@->message );
            return;
        }

        # Get URL from SQS
        $res = eval { $self->{sqs}->GetQueueUrl( QueueName => $queue_name ) };
        if ( $@ && $@->isa('Paws::Exception') ) {
            $log->error( "Failed to get queue $queue_name after creating: " . $@->message );
            return;
        }
    }

    my $queue_url = $res->QueueUrl;

    # This is possibly racy, but hopefully attributes don't change much, and
    # also that we don't run N versions of the code in prod at the same time...
    # but it beats forgetting to update SQS and/or having to do it by hand
    # all the time
    $res = eval {
        $self->{sqs}->GetQueueAttributes(
            QueueUrl       => $queue_url,
            AttributeNames => [ keys %$queue_attrs ],
        );
    };
    if ( $@ && $@->isa('Paws::Exception') ) {
        $log->warn( 'Failed to get queue attributes for ', $queue_name, ': ', $@->message );
        next;
    }

    $log->debug( 'Checking queue attributes for ', $queue_name, '...' );
    foreach my $attr ( sort keys %$queue_attrs ) {

        # Coerce to strings for easy comparisons
        my $val_local = "" . $queue_attrs->{$attr};
        my $val_prod  = "" . $res->Attributes->{$attr};
        next if $val_local eq $val_prod;

        $log->info(
            sprintf(
                'Changing attribute %s of queue %s from %s to %s.',
                $attr, $queue_name, $val_prod, $val_local
            )
        );
        eval {
            $self->{sqs}->SetQueueAttributes(
                QueueUrl   => $queue_url,
                Attributes => { $attr => $val_local }
            );
        };
        if ( $@ && $@->isa('Paws::Exception') ) {
            $log->warn( 'Failed to set queue attributes for ', $queue_name, ': ', $@->message );
            next;
        }
    }

    # Stick it in the queue
    return ( $queue_name, $self->{queues}->{$queue_name} = $queue_url );
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
            DW::Stats::increment( 'dw.taskqueue.sent_messages',  scalar(@messages), $tags );
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
    unless ( $messages && ref $messages eq 'ARRAY' && scalar @$messages >= 1 ) {
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

1;
