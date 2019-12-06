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
    my ( $userid, $subid, $eparams ) = @$a;
    my $u = LJ::load_userid($userid);

    $log->debug( 'Processing event for user: ', $u->user, '(', $u->id, ') subscription ', $subid );

    my $evt   = LJ::Event->new_from_raw_params(@$eparams);
    my $subsc = $evt->get_subscriptions( $u, $subid );

    # if the subscription doesn't exist anymore, we're done here
    # (race: if they delete the subscription between when we start processing
    # events and when we get here, LJ::Subscription->new_by_id will return undef)
    # We won't reach here if we get DB errors because new_by_id will die, so we're
    # safe to mark the job completed and return.
    return DW::Task::COMPLETED unless $subsc;

    # If the user hasn't logged in in a year, complete the sub and let's
    # move on
    my $user_idle_days = int( ( time() - $u->get_timeactive ) / 86400 );
    return DW::Task::COMPLETED if $user_idle_days > 365 && !$LJ::_T_CONFIG;

    # if the user deleted their account (or otherwise isn't visible), bail
    return DW::Task::COMPLETED unless $u->is_visible || $evt->is_significant;

    # TODO: do inbox notification method here, first.

    # NEXT: do sub's ntypeid, unless it's inbox, then we're done.
    $subsc->process($evt)
        or die
        "Failed to process notification method for userid=$userid/subid=$subid, evt=[@$eparams]\n";
    return DW::Task::COMPLETED;
}

1;

