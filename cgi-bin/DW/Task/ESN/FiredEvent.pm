#!/usr/bin/perl
#
# DW::Task::ESN::FiredEvent
#
# ESN worker that kicks off the process, called whenever an event has fired and
# enables us to do initial subscription processing.
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

package DW::Task::ESN::FiredEvent;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::Task::ESN::FindSubsByCluster;
use DW::TaskQueue;
use LJ::ESN;
use LJ::Event;

use base 'DW::Task';

sub work {
    my $self = $_[0];
    my $a    = $self->args;

    my $incr = sub {
        my ( $phase, $incr, $tags ) = @_;
        push @{ $tags ||= [] }, "etypeid:$a->[0]";
        DW::Stats::increment( 'dw.esn.firedevent.' . $phase, $incr // 1, $tags );
    };

    $incr->('started');

    my $evt = eval { LJ::Event->new_from_raw_params(@$a) };
    unless ($evt) {
        $log->error( 'Failed to load event from raw params: ', join( ', ', @$a ) );
        $incr->( 'failed', 1, ['err:LoadEvent'] );
        return DW::Task::FAILED;
    }

    $evt->configure_logger;

    $log->debug( 'Processing event from raw params: ', join( ', ', @$a ) );

    # step 1:  see if we can split this into a bunch of ProcessSub directly.
    # we can only do this if A) all clusters are up, and B) subs is reasonably
    # small.  say, under 5,000.
    my $split_per_cluster = 0;    # bool: died or hit limit, split into per-cluster jobs
    my @subs;
    foreach my $cid (@LJ::CLUSTERS) {
        my @more_subs = eval {
            $evt->subscriptions(
                cluster => $cid,
                limit   => $LJ::ESN::MAX_FILTER_SET - @subs + 1
            );
        };
        if ($@) {
            $log->debug( 'Failed scanning for subscriptions from cluster: ', $cid );

            # if there were errors (say, the cluster is down), abort!
            # that is, abort the fast path and we'll resort to
            # per-cluster scanning
            $split_per_cluster = "some_error";
            last;
        }

        $log->debug(
            sprintf( 'Found %d subscriptions from cluster %d.', scalar(@more_subs), $cid ) );

        push @subs, @more_subs;
        if ( @subs > $LJ::ESN::MAX_FILTER_SET ) {
            $split_per_cluster = "hit_max";
            last;
        }
    }

    # If there are no subscriptions and we didn't hit an edge case, exit now
    unless ( @subs || $split_per_cluster ) {
        $log->debug('No subscriptions found for event.');
        $incr->( 'completed', 1, ['err:NoSubsNoSplit'] );
        return DW::Task::COMPLETED;
    }

    # this is the slow/safe/on-error/lots-of-subscribers path
    my @subjobs;
    if ($split_per_cluster) {
        my $params = $evt->raw_params;
        foreach my $cid (@LJ::CLUSTERS) {
            push @subjobs, DW::Task::ESN::FindSubsByCluster->new( $cid, $params );
        }
        $log->debug(
            sprintf(
                'Slow path: exploding job into %d cluster scan jobs because: %s',
                scalar(@subjobs), $split_per_cluster
            )
        );
    }
    else {
        # the fast path, filter those max 5,000 subscriptions down to ones that match,
        # then split right into processing those notification methods
        @subjobs = LJ::ESN->tasks_of_unique_matching_subs( $evt, @subs );
        $log->debug(
            sprintf( 'Fast path: exploding job into %d processing jobs.', scalar(@subjobs) ) );
    }

    # And if those subscriptions didn't turn into actual jobs, nothing to do
    unless (@subjobs) {
        $log->debug('No notification jobs found for subscriptions.');
        $incr->( 'completed', 1, [ 'err:NoSubsWithSplit', 'split:' . $split_per_cluster ] );
        return DW::Task::COMPLETED;
    }

    unless ( DW::TaskQueue->send(@subjobs) ) {
        $incr->( 'completed', 1, ['err:FailedSend'] );
        return DW::Task::FAILED;
    }

    $incr->( 'completed', 1, ['err:None'] );
    return DW::Task::COMPLETED;
}

1;

