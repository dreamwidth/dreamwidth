#!/usr/bin/perl

# Tests LJ::NotificationInbox and LJ::NotificationItem

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';

#plan tests =>;
plan skip_all => 'Fix this test! LJ/Event/Befriended.pm is missing';

# Set more manageable limit for testing
$LJ::CAP_DEF{'inbox_max'} = 10;

use LJ::Test qw(temp_user memcache_stress);

use LJ::NotificationInbox;
use LJ::NotificationItem;
use LJ::Event;
#use LJ::Event::Befriended;

my $u = temp_user();
my $u2 = temp_user();
ok($u && $u2, "Got temp users");
my $max = $u->get_cap('inbox_max');

sub run_tests {
    my $q;
    my $rv;
    my @notifications;
    my $qid;
    my $evt;
    my $qitem;

    # create a queue
    {
        $q = $u->notification_inbox;
        ok($q, "Got queue");
    }

    # create an event to enqueue and enqueue it
    {
        $evt = LJ::Event::Befriended->new($u, $u2);
        ok($evt, "Made event");
        # enqueue this event
        $qid = $q->enqueue(event => $evt);
        ok($qid, "Enqueued event");
    }

    # check the queued events and make sure we get what we put in
    {
        @notifications = $q->items;
        ok(@notifications, "Got notifications list");
        ok((scalar @notifications) == 1, "Got one item");
        $qitem = $notifications[0];
        ok($qitem, "Item exists");
        is($qitem->event->etypeid, $evt->etypeid, "Event is same");
    }

    # test states
    {
        # default is unread
        ok($qitem->unread, "Item is marked as unread");
        ok(! $qitem->read, "Item is not marked as read");

        # mark it read
        $qitem->mark_read;
        ok($qitem->read, "Item is marked as read");
        ok(! $qitem->unread, "Item is not marked as unread");

        # mark it unread
        $qitem->mark_unread;
        ok($qitem->unread, "Item is marked as unread");
        ok(! $qitem->read, "Item is not marked as read");
    }

    # delete this from the queue
    {
        $rv = $qitem->delete;
        ok($rv, "Deleting from queue");
        # we should not have any items left in the queue now
        @notifications = $q->items;
        ok(!@notifications, "No items left in queue");
    }

    # test the max number of events
    {
        $evt = LJ::Event::Befriended->new($u, $u2);
        # enqueue max numbers of events
        for (my $i=1; $i<=$max; $i++) {
            $q->enqueue(event => $evt);
        }
        @notifications = $q->items;
        ok((scalar @notifications) == $max, "Got max number of items");

        my $evt2 = LJ::Event::Befriended->new($u, $u2);
        my $qid1 = $q->enqueue(event => $evt);
        my $qid2 = $q->enqueue(event => $evt2);
        @notifications = $q->items;
        is((scalar @notifications), $max, "Not over max number of items");

        $q->add_bookmark($qid1->qid);
        $q->add_bookmark($qid2->qid);
        my $qid3 = $q->enqueue(event => $evt);
        my $qid4 = $q->enqueue(event => $evt);
        @notifications = $q->items;
        is((scalar @notifications), ($max + 2), "Bookmarks don't count towards max number of items");

        for (my $i=1; $i<=$max+2; $i++) {
            $q->enqueue(event => $evt);
        }
        @notifications = $q->items;
        my %nitem; # hash of qids in queue
        foreach my $qitem (@notifications) {
            $nitem{$qitem->qid} = 1;
        }
        my $is_enqueued = ($nitem{$qid1->qid} && $nitem{$qid2->qid});
        ok($is_enqueued, "Bookmarks always stay in queue");

        # cleanup
        foreach my $qitem (@notifications) {
            $qitem->delete;
        }
    }

}

memcache_stress {
    run_tests();
};

1;
