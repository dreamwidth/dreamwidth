#!/usr/bin/perl
#
# DW::Task::ESN::FindSubsByCluster
#
# ESN worker to do final subscription processing.
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

package DW::Task::ESN::FindSubsByCluster;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::TaskQueue;
use DW::Task::ESN::FilterSubs;
use LJ::Event;
use LJ::ESN;

use base 'DW::Task';

sub work {
    my $self = $_[0];
    my $a    = $self->args;
    my ( $cid, $e_params ) = @$a;

    my $incr = sub {
        my ( $phase, $incr, $tags ) = @_;
        push @{ $tags ||= [] }, "etypeid:$e_params->[0]";
        DW::Stats::increment( 'dw.esn.findsubsbycluster.' . $phase, $incr // 1, $tags );
    };

    $incr->('started');

    my $evt = eval { LJ::Event->new_from_raw_params(@$e_params) };
    unless ($evt) {
        $log->error( 'Failed to load event from raw params: ', join( ', ', @$e_params ) );
        $incr->( 'failed', 1, ['err:LoadEvent'] );
        return DW::Task::FAILED;
    }

    $evt->configure_logger;

    my $dbch = LJ::get_cluster_master($cid);
    unless ($dbch) {
        $log->error( "Couldn't connect to cluster: ", $cid );
        $incr->( 'failed', 1, ['err:GetClusterMaster'] );
        return DW::Task::FAILED;
    }

    my @subs = $evt->subscriptions( cluster => $cid );

    # fast path:  job from phase2 to phase4, skipping filtering.
    if ( @subs <= $LJ::ESN::MAX_FILTER_SET ) {
        $log->debug( 'Fast path: only found ', scalar(@subs), ' subscriptions.' );
        DW::TaskQueue->send( LJ::ESN->tasks_of_unique_matching_subs( $evt, @subs ) );
        return DW::Task::COMPLETED;
    }

    # checking is bypassed for that user.
    my %by_userid;
    foreach my $s (@subs) {
        push @{ $by_userid{ $s->userid } ||= [] }, $s;
    }

    my @subjobs;

    # now group into sets of 5,000:
    while (%by_userid) {
        my @set;
    BUILD_SET:
        while ( %by_userid && @set < $LJ::ESN::MAX_FILTER_SET ) {
            my $finish_set = 0;
        UID:
            foreach my $uid ( keys %by_userid ) {
                my $subs   = $by_userid{$uid};
                my $size   = scalar @$subs;
                my $remain = $LJ::ESN::MAX_FILTER_SET - @set;

                # if a user for some reason has more than 5,000 matching subscriptions,
                # uh, skip them.  that's messed up.
                if ( $size > $LJ::ESN::MAX_FILTER_SET ) {
                    delete $by_userid{$uid};
                    next UID;
                }

                # if this user's subscriptions don't fit into the @set,
                # move on to the next user
                if ( $size > $remain ) {
                    $finish_set = 1;
                    next UID;
                }

                # add user's subs to this set and delete them.
                push @set, @$subs;
                delete $by_userid{$uid};
            }
            last BUILD_SET if $finish_set;
        }

        # $sublist is [ [userid, subid]+ ]. also, pass clusterid through
        # to filtersubs so we can check that we got a subscription for that
        # user from the right cluster. (to avoid user moves with old data
        # on old clusters from causing duplicates). easier to do it there
        # than here, to avoid a load_userids call.
        my $sublist = [ map { [ $_->userid + 0, $_->id + 0 ] } @set ];
        push @subjobs, DW::Task::ESN::FilterSubs->new( $e_params, $sublist, $cid );
    }

    $log->debug( 'Sending ', scalar(@subjobs), ' filtering subjobs.' );

    DW::TaskQueue->send(@subjobs);
    return DW::Task::COMPLETED;
}

1;
