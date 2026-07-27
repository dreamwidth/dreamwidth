#!/usr/bin/perl
#
# DW::Task
#
# Base class for asynchronously executed tasks.
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

package DW::Task;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use LJ::JSON;
use MIME::Base64 qw/ encode_base64 decode_base64 /;
use Storable qw/ nfreeze thaw /;

use constant COMPLETED => 100;
use constant FAILED    => 101;

sub new {
    my ( $class, @args ) = @_;

    my $self = { args => \@args };
    return bless $self, $class;
}

sub args {
    my $self = $_[0];

    return $self->{args};
}

sub with_dedup {
    my ( $self, %opts ) = @_;
    $self->{uniqkey}   = $opts{uniqkey};
    $self->{dedup_ttl} = $opts{dedup_ttl};
    return $self;
}

sub uniqkey {
    return $_[0]->{uniqkey};
}

sub dedup_ttl {
    return $_[0]->{dedup_ttl};
}

sub receive_count {
    my ( $self, $val ) = @_;
    $self->{_receive_count} = $val if defined $val;
    return $self->{_receive_count} || 0;
}

# serialize()
#
# Serializes this task to a string suitable for transport (SQS, local disk).
#
# $LJ::TASK_QUEUE_JSON controls what fraction of messages are serialized as
# JSON. Set to 0 (default) for all Storable, 1.0 for all JSON, or a float
# between 0 and 1 for percentage rollout (e.g. 0.01 = 1% JSON).
#
# Falls back to legacy Storable format if JSON encoding fails (e.g. args
# contain non-JSON-safe data like blessed objects or binary strings).
sub serialize {
    my ($self) = @_;

    if ( ( $LJ::TASK_QUEUE_JSON || 0 ) >= 1 || rand() < ( $LJ::TASK_QUEUE_JSON || 0 ) ) {
        my %data = (
            class => ref($self),
            args  => $self->{args},
        );
        $data{uniqkey}   = $self->{uniqkey}   if defined $self->{uniqkey};
        $data{dedup_ttl} = $self->{dedup_ttl} if defined $self->{dedup_ttl};

        my $json = eval { to_json( \%data ) };
        if ($@) {
            my $task_class = ref($self);
            $log->warn(
                'JSON serialization failed for ', $task_class,
                ', falling back to Storable: ',   $@
            );
            DW::Stats::increment( 'dw.taskqueue.serialize', 1,
                [ 'format:storable', 'reason:json_fallback', "task_class:$task_class" ] );
        }
        else {
            DW::Stats::increment( 'dw.taskqueue.serialize', 1, ['format:json'] );
            return 'v2:json:' . $json;
        }
    }

    # Legacy Storable format (default, or fallback on JSON encoding failure)
    DW::Stats::increment( 'dw.taskqueue.serialize', 1, ['format:storable'] );
    return encode_base64( nfreeze($self) );
}

# deserialize($body)
#
# Class method. Deserializes a task from a string. Handles both v2 JSON format
# and legacy Storable format for backwards compatibility during migration.
sub deserialize {
    my ( $class, $body ) = @_;

    # v2 JSON format: "v2:json:{...}"
    if ( $body =~ s/^v2:json:// ) {
        my $data       = from_json($body);
        my $task_class = $data->{class};

        $log->logcroak( 'Invalid task class: ', $task_class // '<undef>' )
            unless $task_class && $task_class =~ /^DW::Task(?:::\w+)+$/;

        eval "use $task_class;";
        $log->logcroak( 'Failed to load task class ', $task_class, ': ', $@ ) if $@;

        my $self = bless { args => $data->{args} }, $task_class;
        $self->{uniqkey}   = $data->{uniqkey}   if defined $data->{uniqkey};
        $self->{dedup_ttl} = $data->{dedup_ttl} if defined $data->{dedup_ttl};
        DW::Stats::increment( 'dw.taskqueue.deserialize', 1, ['format:json'] );
        return $self;
    }

    # Legacy Storable format (base64-encoded nfreeze)
    DW::Stats::increment( 'dw.taskqueue.deserialize', 1, ['format:storable'] );
    return thaw( decode_base64($body) );
}

sub queue_attributes {
    my ( $self, %opts ) = @_;

    my %attrs = (
        DelaySeconds                  => 0,
        MaximumMessageSize            => 262_144,
        MessageRetentionPeriod        => 345_600,
        ReceiveMessageWaitTimeSeconds => 10,
        VisibilityTimeout             => 300,
    );

    if ( $opts{dlq} ) {
        my $arn =
            sprintf( 'arn:aws:sqs:%s:%d:%s', $LJ::SQS{region}, $LJ::SQS{account}, $opts{dlq} );
        $attrs{RedrivePolicy} = "{\"deadLetterTargetArn\":\"$arn\",\"maxReceiveCount\":3}";
    }

    return %attrs;
}

1;
