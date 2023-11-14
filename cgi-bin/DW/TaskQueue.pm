#!/usr/bin/perl
#
# DW::TaskQueue
#
# Library for queueing and executing jobs.
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

package DW::TaskQueue;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::TaskQueue::SQS;
use DW::TaskQueue::LocalDisk;

my $_queue;

sub get {
    my $class = $_[0];

    return $_queue if defined $_queue;

    # Determine what kind of queue object to build, depending on if we're
    # running locally or not
    if ( exists $LJ::SQS{region} ) {
        return $_queue = DW::TaskQueue::SQS->init(%LJ::SQS);
    }

    # If we're a dev server, allow the local mode (not allowed in production,
    # it's really crappy)
    if ($LJ::IS_DEV_SERVER) {
        return $_queue = DW::TaskQueue::LocalDisk->init();
    }

    $log->logcroak('Unable to instantiate any DW::TaskQueue modules.');
}

sub send {
    my ( $class, @args ) = @_;

    $class->get->send(@args);
}

sub receive {
    my ( $class, @args ) = @_;

    $class->get->receive(@args);
}

sub completed {
    my ( $class, @args ) = @_;

    $class->get->completed(@args);
}

sub dispatch {
    my ( $self, @tasks ) = @_;
    return undef unless @tasks;

    $self = $self->get unless ref $self;

    # This is a shim function that inspects the tasks being sent and dispatches
    # them to the appropriate task queueing system.
    my ( @schwartz_jobs, @tsq_tasks );
    foreach my $task (@tasks) {
        if ( $task->isa('TheSchwartz::Job') ) {
            push @schwartz_jobs, $task;
        }
        elsif ( $task->isa('DW::Task') ) {
            push @tsq_tasks, $task;
        }
        elsif ( $task->isa('LJ::Event') ) {

            # Do the TSQ check, because these tasks could go either way, and we
            # want to be able to ramp up the traffic slowly.
            if ( $LJ::ESN_OVER_SQS && rand() < $LJ::ESN_OVER_SQS ) {
                push @tsq_tasks, $task->fire_task;
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

    # Dispatch to TaskQueue
    if (@tsq_tasks) {
        $log->debug( 'Inserting ' . scalar(@tsq_tasks) . ' tasks into TaskQueue.' );
        $rv &&= $self->send(@tsq_tasks);
    }

    # Returns the "worse" of the return values. If either are falsey, we will
    # return a false value.
    return $rv;
}

sub start_work {
    my ( $self, $class, %opts ) = @_;

    $opts{message_timeout_secs} ||= 0;

    $self = $self->get unless ref $self;

    eval "use $class;";

    my $start_time    = time();
    my $messages_done = 0;

    $log->info( sprintf( '[%s %0.3fs] Worker starting', $class, 0.0 ) );

    while (1) {
        my $recv_start_time = time();
        if ( $opts{exit_after_secs} && ( $recv_start_time - $start_time > $opts{exit_after_secs} ) )
        {
            $log->info(
                sprintf(
                    '[%s] Exiting after %d seconds of work, as requested.',
                    $class, $opts{exit_after_secs}
                )
            );
            return;
        }

        if ( $opts{exit_after_messages} && ( $messages_done >= $opts{exit_after_messages} ) ) {
            $log->info(
                sprintf(
                    '[%s] Exiting after %d messages done, as requested.',
                    $class, $opts{exit_after_messages}
                )
            );
            return;
        }

        my $messages  = $self->receive( $class, 10 );
        my $recv_time = time() - $recv_start_time;

        unless ( @{ $messages || [] } ) {
            $log->debug( sprintf( '[%s %0.3fs] Receive finished, empty', $class, $recv_time ) );
            next;
        }

        $log->debug(
            sprintf(
                '[%s %0.3fs] Receive finished, %d messages',
                $class, $recv_time, scalar(@$messages)
            )
        );

        my ( @completed,       @failed );
        my ( $work_start_time, $work_end_time );
        foreach my $message_pair (@$messages) {
            my ( $handle, $message ) = @$message_pair;

            # Record earliest start time of any coroutine
            my $local_start_time = time();
            $work_start_time = $local_start_time
                if $local_start_time < $work_start_time || !defined $work_start_time;

            my ( $res, $abort );
            eval {
                local $SIG{ALRM} = sub {
                    $log->error(
                        sprintf(
'[%s] Operation timed out after %d seconds. Exiting worker. Message: %s',
                            $class, $opts{message_timeout_secs}, $handle
                        )
                    );
                    $abort = 1;
                };
                alarm $opts{message_timeout_secs};
                $res = $message->work($handle);
            };
            alarm 0;
            die if $@;    # Reraise if the work call died.

            # Clear out MDC so we don't continue to log with whatever the worker might
            # have put into context
            Log::Log4perl::MDC->remove;
            return if $abort;

            $messages_done++;

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
        }

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

1;
