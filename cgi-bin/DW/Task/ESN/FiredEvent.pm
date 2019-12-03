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

    my $evt = eval { LJ::Event->new_from_raw_params(@$a) }
        or return DW::Task::FAILED;

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

            # if there were errors (say, the cluster is down), abort!
            # that is, abort the fast path and we'll resort to
            # per-cluster scanning
            $split_per_cluster = "some_error";
            last;
        }

        push @subs, @more_subs;
        if ( @subs > $LJ::ESN::MAX_FILTER_SET ) {
            $split_per_cluster = "hit_max";
            warn "Hit max!  over $LJ::ESN::MAX_FILTER_SET = @subs\n" if $ENV{DEBUG};
            last;
        }
    }

    # this is the slow/safe/on-error/lots-of-subscribers path
    if ($split_per_cluster) {
        my @subjobs;
        my $params = $evt->raw_params;
        foreach my $cid (@LJ::CLUSTERS) {
            push @subjobs, DW::Task::ESN::FindSubsByCluster->new( $cid, $params );
        }
        DW::TaskQueue->get->send(@subjobs);
        return DW::Task::COMPLETED;
    }

    # the fast path, filter those max 5,000 subscriptions down to ones that match,
    # then split right into processing those notification methods
    DW::TaskQueue->get->send( LJ::ESN->tasks_of_unique_matching_subs( $evt, @subs ) );
    return DW::Task::COMPLETED;
}

1;

