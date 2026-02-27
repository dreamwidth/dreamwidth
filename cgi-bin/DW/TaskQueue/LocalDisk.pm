#!/usr/bin/perl
#
# DW::TaskQueue::LocalDisk
#
# Library for queueing and executing jobs via local disk. This is in no way
# production quality code, only use it in development.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::TaskQueue::LocalDisk;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use MIME::Base64 qw/ encode_base64 decode_base64 /;
use Storable qw/ nfreeze thaw /;
use Time::HiRes qw/ time /;
use UUID::Tiny qw/ :std /;

use DW::Task;

sub init {
    my $class = $_[0];

    $log->debug("Initializing taskqueue for LocalDisk");

    mkdir("$LJ::HOME/var/taskqueue") unless -d "$LJ::HOME/var/taskqueue";

    my $self = { path => "$LJ::HOME/var/taskqueue", queues => {} };
    return bless $self, $class;
}

sub _queue_dir {
    my ( $self, $task ) = @_;

    my $queue_name = lc( ref $task || $task );
    $queue_name =~ s/::/-/g;

    my $dir = $self->{path} . '/' . $queue_name;
    mkdir($dir) unless -d $dir;

    return $dir;
}

sub send {
    my ( $self, @tasks ) = @_;
    return undef unless @tasks;

    my $dir = $self->_queue_dir( $tasks[0] );

    # Send batches of messages, limited by count or size
    my @messages;
    my ( $sent_bytes, $ctr ) = ( 0, 0 );

    foreach my $task (@tasks) {

        # Pickle the message and write to a file with a random name
        my $uuid = create_uuid_as_string(UUID_V4);
        open FILE, ">$dir/$uuid"
            or $log->logcroak('Failed to open message file!');
        print FILE encode_base64( nfreeze($task) );
        close FILE;
    }

    return 1;
}

sub receive {
    my ( $self, $class, $count, $wait_secs ) = @_;
    $count ||= 10;
    $wait_secs = 10 unless defined $wait_secs;

    my $dir = $self->_queue_dir($class);

    # To emulate SQS, we will wait for messages up to $wait_secs seconds.
    # Always scan at least once so that wait_secs=0 (non-blocking) works.
    my @tasks;
    my $abort_after = time() + $wait_secs;
    while (1) {
        opendir DIR, $dir or $log->logcroak('Failed to open directory!');
        @tasks = grep { /^[0-9a-f]/ && -f "$dir/$_" } readdir DIR;
        closedir DIR;

        last if @tasks || time() >= $abort_after;
    }

    my $thaw_task = sub {
        local $/ = undef;
        open FILE, "<$dir/$_[0]" or $log->logcroak('Unable to open file.');
        my $task = thaw( decode_base64(<FILE>) );
        close FILE;
        return $task;
    };

    return [ map { [ $_, $thaw_task->($_) ] } @tasks ];
}

sub completed {
    my ( $self, $class, @handles ) = @_;
    return unless @handles;

    my $dir = $self->_queue_dir($class);

    foreach my $handle (@handles) {
        unlink "$dir/$handle";
    }
}

1;
