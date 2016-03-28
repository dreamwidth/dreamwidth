# t/subscription-flags.t
#
# Test LJ::Subscription set_flag and clear_flag.
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

use Test::More tests => 10;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Subscription;
use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);

run_tests();

sub run_tests {
    my $u = temp_user();

    # create a subscription
    my $subscr = LJ::Subscription->create(
                                          $u,
                                          event => 'JournalNewEntry',
                                          journalid => 0,
                                          method => 'Inbox',
                                          );

    ok($subscr, "Got subscription");

    # test flag setter/accessors
    {
        my $flags = $subscr->flags;
        is($flags, 0, "No flags set");

        # set inactive flag
        $subscr->_deactivate;
        ok(! $subscr->active, "Deactivated");

        # make sure inactive flag is set
        $flags = $subscr->flags;
        is($flags, LJ::Subscription::INACTIVE, "Inactive flag set");

        # clear inactive flag
        $subscr->activate;

        # make sure inactive flag is unset
        $flags = $subscr->flags;
        is($flags, 0, "Inactive flag unset");

        # set a bunch of flags and clear one
        $subscr->set_flag(1);
        $subscr->set_flag(2);
        $subscr->set_flag(4);
        $subscr->set_flag(8);
        $subscr->clear_flag(4);

        is($subscr->flags, 11, "Cleared one flag ok");

        # clear flags and set disabled and inactive

        $subscr->clear_flag(1);
        $subscr->clear_flag(2);
        $subscr->clear_flag(8);

        $subscr->set_flag(LJ::Subscription::DISABLED);
        $subscr->set_flag(LJ::Subscription::INACTIVE);
        ok(! $subscr->active, "Inactive");
        ok(! $subscr->enabled, "Disabled");

        # clear disable and make sure still inactive
        $subscr->enable;
        ok(! $subscr->active, "Inactive");
        ok($subscr->enabled, "Enabled");
    }
}
