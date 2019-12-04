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

use MIME::Base64;
use Paws;
use Paws::Credential::InstanceProfile;
use Storable qw/ nfreeze thaw /;
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

    return $self->{queues}->{$queue_name}
        if exists $self->{queues}->{$queue_name};

    my $res = eval { $self->{sqs}->GetQueueUrl( QueueName => $queue_name ) };
    if ( $@ && $@->isa('Paws::Exception') ) {
        $log->warn("Failed to get queue $queue_name, creating.");

        $res = eval { $self->{sqs}->CreateQueue( QueueName => $queue_name ) };
        if ( $@ && $@->isa('Paws::Exception') ) {
            $log->error( "Failed to create queue $queue_name: " . $@->message );
            return undef;
        }

        $res = eval { $self->{sqs}->GetQueueUrl( QueueName => $queue_name ) };
        if ( $@ && $@->isa('Paws::Exception') ) {
            $log->error( "Failed to get queue $queue_name after creating: " . $@->message );
            return undef;
        }
    }

    return $self->{queues}->{$queue_name} = $res->QueueUrl;
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

    my $queue = $self->_get_queue_for_task( $tasks[0] )
        or return undef;

    # Send batches of messages, limited by count or size
    my @messages;
    my $sent_bytes = 0;

    my $send = sub {
        $log->debug( 'Sending ', length(@messages), ' messages: ', $sent_bytes, ' bytes.' );
        my $res =
            eval { $self->{sqs}->SendMessageBatch( QueueUrl => $queue, Entries => \@messages ) };
        if ( $@ && $@->isa('Paws::Exception') ) {
            $log->error( 'Failed to send SQS message batch: ' . $@->message );
            return undef;
        }

        @messages   = ();
        $sent_bytes = 0;
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
        push @messages, { Id => 'id-' . $sent_bytes, MessageBody => $body };
    }

    # If there are any messages left send them
    if (@messages) {
        $send->() or return undef;
    }

    return $sent_bytes > 0 ? 1 : undef;
}

sub _offload_large_message_if_necessary {
    my ( $self, $message ) = @_;

    $message = encode_base64( nfreeze($message) );
    return $message if length $message < LARGE_MESSAGE_CUTOFF;

    my $uuid = create_uuid_as_string(UUID_V4);
    my $rv   = DW::BlobStore->store( tasks_offload => $uuid, \$message );
    unless ($rv) {
        $log->error('Failed to offload task to BlobStore!');
        return undef;
    }

    return 'offloaded:' . $uuid;
}

sub _reload_large_message_if_necessary {
    my ( $self, $message ) = @_;

    my $uuid = $1
        if $message =~ /^offloaded:(.+?)$/;
    return $message unless $uuid;

    my $rv = DW::BlobStore->retrieve( tasks_offload => $uuid );
    unless ($rv) {
        $log->error( 'Failed to reload task from BlobStore: ' . $uuid );
        return undef;
    }

    return $$rv;
}

sub receive {
    my ( $self, $class, $count ) = @_;
    $count ||= 10;

    $self = $self->get unless ref $self;

    my $queue = $self->_get_queue_for_task($class)
        or return undef;

    my $res = eval {
        $self->{sqs}->ReceiveMessage(
            QueueUrl            => $queue,
            MaxNumberOfMessages => $count,
            WaitTimeSeconds     => 10
        );
    };
    if ( $@ && $@->isa('Paws::Exception') ) {
        $log->warn( 'Failed to retrieve SQS messages: ' . $@->message );
        return undef;
    }

    my $messages = $res->Messages;
    return undef
        unless $messages && ref $messages eq 'ARRAY' && length @$messages >= 1;

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

    my $queue = $self->_get_queue_for_task($class)
        or return undef;

    my $res = eval {
        my $idx = 0;
        $self->{sqs}->DeleteMessageBatch(
            QueueUrl => $queue,
            Entries  => [ map { { Id => $idx++, ReceiptHandle => $_ } } @handles ]
        );
    };
    if ( $@ && $@->isa('Paws::Exception') ) {
        $log->warn( 'Failed to delete message batch: ' . $@->message );
    }

    # TODO: We could return information about which messages failed to complete,
    # and then do something else with them, but not sure what to do yet.
}

sub start_work {
    my ( $self, $class ) = @_;

    $self = $self->get unless ref $self;

    eval "use $class;";

    while (1) {
        my @completed;
        my $messages = $self->receive( $class, 10 );

        $log->warn( 'Got ' . scalar(@$messages) . ' messages for task: ' . $class );
        foreach my $message_pair (@$messages) {
            my ( $handle, $message ) = @$message_pair;
            my $res = $message->work;
            if ( $res == DW::Task::COMPLETED ) {
                push @completed, $handle;
            }
            else {
                $log->warn( 'Message failed to complete: ' . $handle . ' (' . $class . ')' );
            }
        }

        if (@completed) {
            $log->warn( 'Completing ' . scalar(@completed) . ' messages for task: ' . $class );
            $self->completed( $class, @completed );
        }
    }
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
