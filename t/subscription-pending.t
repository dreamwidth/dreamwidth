# t/subscription-pending.t
#
# Test LJ::Subscription::Pending
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

use Test::More tests => 9;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Subscription::Pending;
use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);

my $u = temp_user();
ok( $u, "Got a \$u" );
my $u2 = temp_user();

my %args = (
    journal => $u2,
    event   => "JournalNewEntry",
    method  => "Inbox",
    arg1    => 42,
    arg2    => 69,
);

my $ps = LJ::Subscription::Pending->new( $u, %args );

ok( $ps, "Got pending subscription" );

my @subs = $u->find_subscriptions(%args);
ok( !@subs, "Didn't subscribe" );

my $frozen = $ps->freeze;
like( $frozen, qr/\d+-\d+/, "Froze" );

my $thawed = LJ::Subscription::Pending->thaw( $frozen, $u );
ok( $thawed, "Thawed" );

is_deeply( $ps, $thawed, "Got same subscription back" );

my $subscr = $thawed->commit($u);
ok( $subscr, "committed" );

@subs = $u->find_subscriptions(%args);
ok( ( scalar @subs ) == 1, "Subscribed ok" );

is( $subs[0]->arg1, $subscr->arg1, "OK subscription" );

$subscr->delete;
