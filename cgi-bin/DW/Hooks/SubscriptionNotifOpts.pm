#!/usr/bin/perl
#
# DW::Hooks::SubscriptionNotifOpts
#
# Implements logic for a subscription's status on the notifications settings page.
# Originally part of LJ::subscribe_interface.
#
# Authors:
#      Jen Griffin <kareila@livejournal.com> (moved into hook)
#
# Copyright (c) 2009-2023 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Hooks::SubscriptionNotifOpts;

use strict;
use LJ::Hooks;

LJ::Hooks::register_hook(
    'subscription_notif_options',
    sub {
        my (%opts) = @_;

        my $u           = delete $opts{u};
        my $sub_data    = delete $opts{sub_data};
        my $pending_sub = delete $opts{pending_sub};
        my $def_notes   = delete $opts{def_notes};

        my $is_tracking_category = delete $opts{is_tracking_category};
        my $num_subs_by_type     = delete $opts{num_subs_by_type};
        my $notify_classes       = delete $opts{notify_classes};

        die "Invalid options passed to subscription_notif_options" if scalar keys %opts;
        die "Invalid user for subscription_notif_options" unless LJ::isu($u);

        if ( !$sub_data->{disabled} && ( $is_tracking_category || $sub_data->{selected} ) ) {
            $num_subs_by_type->{"LJ::NotificationMethod::Inbox"}->{total}++;
            $num_subs_by_type->{"LJ::NotificationMethod::Inbox"}->{active}++
                if $sub_data->{selected};
        }

        # is there an inbox notification for this?
        my %sub_args = $pending_sub->sub_info;
        $sub_args{ntypeid} = LJ::NotificationMethod::Inbox->ntypeid;
        delete $sub_args{flags};
        my ($inbox_sub) = $u->find_subscriptions(%sub_args);

        my @ret;

        foreach my $note_class (@$notify_classes) {
            my $ntypeid = eval { $note_class->ntypeid } or next;
            $sub_args{ntypeid} = $ntypeid;

            my $note_pending = LJ::Subscription::Pending->new( $u, %sub_args );

            my @subs = $u->has_subscription(%sub_args);
            $note_pending = $subs[0] if @subs;

            if ( ( $is_tracking_category || $pending_sub->is_tracking_category )
                && $note_pending->pending )
            {
                # flag this as a "tracking" subscription
                $note_pending->set_tracking;
            }

            # select email method by default
            my $note_selected =
                !$sub_data->{selected} && $note_class eq 'LJ::NotificationMethod::Email';
            $note_selected = 1 if @subs;

            # check the box if it's marked as being selected by default UNLESS
            # there exists an inbox subscription and no email subscription
            my $in_def_notes = grep { $note_class eq $_ } @$def_notes ? 1 : 0;
            $note_selected = 1
                if ( !$inbox_sub || @subs ) && $sub_data->{selected} && $in_def_notes;
            $note_selected &&= $note_pending->active && $note_pending->enabled;

            my $note_disabled = !$pending_sub->enabled;
            $note_disabled = 1 unless $note_class->configured_for_user($u);

            push @ret,
                {
                notify_input_name => $note_pending->freeze,
                note_selected     => $note_selected,
                note_pending      => $note_pending->pending,
                disabled          => $note_disabled,
                ntypeid           => $ntypeid,
                has_subs          => ( scalar @subs ) ? 1 : 0,
                };

            if (   !$note_disabled
                && !$sub_data->{hidden}
                && ( $is_tracking_category || $note_selected ) )
            {
                $num_subs_by_type->{$note_class}->{total}++;
                $num_subs_by_type->{$note_class}->{active}++ if $note_selected;
            }
        }

        return \@ret;
    }
);

1;
