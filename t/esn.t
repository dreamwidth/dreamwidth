# t/esn.t
#
# Test ESN events are fired off and received.
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

use Test::More tests => 15;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

@LJ::EVENT_TYPES = ('LJ::Event::ForTest1', 'LJ::Event::ForTest2');
$LJ::_T_FAST_TEMP_USER = 1;

my $up;
my $u = temp_user();

# create another user and make $u2 watch $u
my $u2 = temp_user();
$u2->add_edge( $u, watch => { nonotify => 1 } );

my ($evt, $evt2);

$evt = eval { LJ::Event::ForTest2->new($u, 5, 39, 8); };
like($@, qr/too many/, "too many args");
$evt = eval { LJ::Event::ForTest2->new($u, "foo"); };
like($@, qr/numeric/, "must be numeric");

{
    # event tests
    $evt = LJ::Event::ForTest1->new($u, 5, 39);
    ok($evt, "made event1");
    $evt2 = LJ::Event::ForTest2->new($u, 5, 39);
    ok($evt, "made event2");

    wipe_typeids();

    ok($evt->etypeid, "got typeid: " . $evt->etypeid);
    is($evt->etypeid, $evt->etypeid, "stayed the same");
    ok($evt->etypeid != $evt2->etypeid, "different typeids");

    is(LJ::Event->class($evt->etypeid),  ref $evt,  "LJ::Event->class");
    is(LJ::Event->class($evt2->etypeid), ref $evt2, "Got correct class");

    my @classes = $evt->all_classes;
    ok(@classes, "Got classes");
    ok(scalar (grep { $_ =~ /ForTest1/ } @classes), "found our class");
}

my $nm = LJ::NotificationMethod::ForTest->new($u);
ok($nm, "Made new email notificationmethod");

{
    # subscribe to an event
    my $subscr = $u2->subscribe(
                                # TODO: Jon, fix this ($evt2 is confusing)
                                etypeid   => $evt2->etypeid,
                                ntypeid   => $nm->ntypeid,
                                arg1      => 69,
                                arg2      => 42,
                                journalid => 0,
                                );

    ok($subscr, "Subscribed ok");

    # see if this user has subscriptions
    my @subs = $evt2->subscriptions;
    ok((scalar @subs) == 1, "One subscription");

    # these are unused at the moment
    $subscr->{flags} ||= 0;
    $subscr->{expiretime} ||= 0;
    $subscr->{is_dirty} = undef;

    is_deeply($subs[0], $subscr, "Subscriptions match");

    # TODO: test notification
    $nm->notify($evt);

    $u2->delete_all_subscriptions;
}


sub wipe_typeids {
    my $tm = LJ::Event->typemap or die;
    $tm->delete_class('LJ::Event::ForTest1');
    $tm->delete_class('LJ::Event::ForTest2');
}


package LJ::Event::ForTest1;
use base 'LJ::Event';
sub zero_journalid_subs_means { "watched" }

package LJ::Event::ForTest2;
use base 'LJ::Event';
sub zero_journalid_subs_means { "watched" }

package LJ::NotificationMethod::ForTest;
use base 'LJ::NotificationMethod';
sub notify {
    my $self = shift;
    die unless $self;

    my @events = @_;

    my $u = $self->{u};
    #warn "Notifying $u->{user}: '" . $events[0]->as_string . "'\n";
}

sub new { return bless { u => $_[1] }, $_[0] }

sub is_common { 1 }

1;

