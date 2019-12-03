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

use DW::Task;

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

sub send {
    my ( $self, @tasks ) = @_;
    return undef unless @tasks;

    my $queue = $self->_get_queue_for_task( $tasks[0] )
        or return undef;

    # Get batches of 10 messages and send them along, since that's all SQS lets us do
    my $sent = 0;
    while ( my @taskset = splice @tasks, 0, 10 ) {
        my @messages;
        foreach my $message (@taskset) {
            my $body = encode_base64( nfreeze($message) );
            if ( length $body > 255_000 ) {

                # TODO: Make it possible to offload large messages to S3 and send
                # references in SQS.
                $log->error('Message too large, dropping task.');
            }
            else {
                push @messages, { Id => $sent++, MessageBody => $body };
            }
        }

        $log->debug( 'Sending ' . length(@messages) . ' messages.' );
        my $res =
            eval { $self->{sqs}->SendMessageBatch( QueueUrl => $queue, Entries => \@messages ) };
        if ( $@ && $@->isa('Paws::Exception') ) {
            $log->error( 'Failed to send SQS message: ' . $@->message );
            return undef;
        }
    }

    return $sent;
}

sub receive {
    my ( $self, $class, $count ) = @_;
    $count ||= 10;

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

    $messages = [ map { [ $_->ReceiptHandle, thaw( decode_base64( $_->Body ) ) ] } @$messages ];
    return $messages;
}

sub completed {
    my ( $self, $class, @handles ) = @_;
    return unless @handles;

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
