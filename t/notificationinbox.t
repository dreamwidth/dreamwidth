# t/notificationinbox.t
#
# Tests LJ::NotificationInbox and LJ::NotificationItem
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use warnings;

use Test::More tests => 58;

use strict;
use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

# Set more manageable limit for testing
$LJ::CAP{$_}->{inbox_max} = 10 foreach (0..15);

use LJ::Test qw(temp_user memcache_stress);

use LJ::NotificationInbox;
use LJ::NotificationItem;
use LJ::Event;
use LJ::Event::AddedToCircle;

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
        $evt = LJ::Event::AddedToCircle->new( $u, $u2, 2 );
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
        $evt = LJ::Event::AddedToCircle->new( $u, $u2, 2 );
        # enqueue max numbers of events
        for (my $i=1; $i<=$max; $i++) {
            $q->enqueue(event => $evt);
        }
        @notifications = $q->items;
        ok((scalar @notifications) == $max, "Got max number of items");

        my $evt2 = LJ::Event::AddedToCircle->new( $u, $u2, 2 );
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
