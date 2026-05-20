#!/usr/bin/perl
#
# DW::Hooks::SubscriptionStats
#
# Implements logic for showing stats on the notifications settings page.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com> (original code)
#      Jen Griffin <kareila@livejournal.com> (moved into hook)
#
# Copyright (c) 2009-2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::SubscriptionStats;

use strict;
use LJ::Hooks;

# Format for $num_subs_by_type:
# {
#     LJ::NotificationMethod::Inbox => { active => x, total => y },
#     LJ::NotificationMethod::Email => ...
# }
#
# For the inbox, "total" includes default subs (those at the top) which are active
# and any subs for tracking an entry/comment, whether active or inactive.
#
# For other notification methods, "total" includes default subs (those at the top)
# which are active, and any subs for tracking an entry/comment, but only where the
# sub is active (because inbox is selected, revealing the notification checkbox).
#
# In both cases, "active" only counts subs which are selected - don't count disabled,
# even if checked, because disabled subscriptions don't count against your limit.

LJ::Hooks::register_hook(
    'subscription_stats',
    sub {
        my ( $u, $num_subs_by_type ) = @_;
        die "Invalid user for subscription_stats" unless LJ::isu($u);

        # There's a bit of a trick here: each row counts as a maximum of one subscription.
        # However, forced subscriptions don't count (e.g., "Someone sends me a message").
        # Also, if we activate an inbox subscription but not its email, the total number
        # of subs per notification method goes out of sync.
        #
        # Regardless, once we hit the limit for *any* method, we get a warning. So we take
        # whichever method has the most total / active and use that figure in our message.

        my $calc_max = sub {
            my ($type) = @_;
            my @vals = sort { $b <=> $a } map { $_->{$type} } values %$num_subs_by_type;
            return @vals ? $vals[0] : 0;
        };

        my $paid_max = LJ::get_cap( 'paid', 'subscriptions' );
        my $u_max    = $u->max_subscriptions;

        # max for total number of subscriptions (generally it is $paid_max)
        my $system_max = $u_max > $paid_max ? $u_max : $paid_max;

        return {
            active     => $calc_max->('active'),
            max_active => $u_max,
            total      => $calc_max->('total'),
            max_total  => $system_max,
        };
    }
);

1;
