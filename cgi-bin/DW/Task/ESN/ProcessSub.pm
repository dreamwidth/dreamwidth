#!/usr/bin/perl
#
# DW::Task::ESN::ProcessSub
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

package DW::Task::ESN::ProcessSub;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use LJ::Event;

use base 'DW::Task';

sub work {
    my $self = $_[0];
    my $a    = $self->args;

    my $failed = sub {
        $log->error( sprintf( $_[0], @_[ 1 .. $#_ ] ) );
        return DW::Task::FAILED;
    };

    my ( $userid, $subid, $eparams ) = @$a;
    Log::Log4perl::MDC->put( 'userid', $userid );

    my $u = LJ::load_userid($userid)
        or return $failed->( 'Failed to load user: %d', $userid );
    Log::Log4perl::MDC->put( 'user', $u->user );

    $log->debug( 'Processing event for user: ', $u->user, '(', $u->id, ') subscription ', $subid );

    my $evt = LJ::Event->new_from_raw_params(@$eparams)
        or return $failed->( 'Failed to get event from params: %s', join( ', ', @$eparams ) );
    $evt->configure_logger;

    my $subsc = $evt->get_subscriptions( $u, $subid )
        or return $failed->(
        'Failed to get subscriptions for: %s(%d) subid %d event (%s)',
        $u->user, $u->id, $subid, join( ', ', @$eparams )
        );

    # if the subscription doesn't exist anymore, we're done here
    # (race: if they delete the subscription between when we start processing
    # events and when we get here, LJ::Subscription->new_by_id will return undef)
    # We won't reach here if we get DB errors because new_by_id will die, so we're
    # safe to mark the job completed and return.
    unless ($subsc) {
        $log->debug('Subscription not found on load, skipping notification.');
        return DW::Task::COMPLETED;
    }

    # If the user hasn't logged in in a year, complete the sub and let's
    # move on
    my $user_idle_days = int( ( time() - $u->get_timeactive ) / 86400 );
    if ( $user_idle_days > 365 && !$LJ::_T_CONFIG ) {
        $log->debug('User inactive, skipping notification.');
        return DW::Task::COMPLETED;
    }

    # if the user deleted their account (or otherwise isn't visible), bail
    unless ( $u->is_visible || $evt->is_significant ) {
        $log->debug('User not visible, and event is not significant, skipping notification.');
        return DW::Task::COMPLETED;
    }

    # Send notification.
    $subsc->process($evt)
        or return $failed->(
        "Failed to process notification method for userid=$userid/subid=$subid, evt=[@$eparams]");
    return DW::Task::COMPLETED;
}

1;

