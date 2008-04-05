# -*-perl-*-

use strict;
use Test::More 'no_plan';
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Subscription::Pending;
use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);

my $u = temp_user();
ok($u, "Got a \$u");
my $u2 = temp_user();

my %args = (
            journal => $u2,
            event   => "JournalNewEntry",
            method  => "Inbox",
            arg1    => 42,
            arg2    => 69,
            );

my $ps = LJ::Subscription::Pending->new($u,
                                        %args
                                        );

ok($ps, "Got pending subscription");

my @subs = $u->find_subscriptions(%args);
ok(!@subs, "Didn't subscribe");

my $frozen = $ps->freeze;
like($frozen, qr/\d+-\d+/, "Froze");

my $thawed = LJ::Subscription::Pending->thaw($frozen, $u);
ok($thawed, "Thawed");

is_deeply($ps, $thawed, "Got same subscription back");

my $subscr = $thawed->commit($u);
ok($subscr, "committed");

@subs = $u->find_subscriptions(%args);
ok((scalar @subs) == 1, "Subscribed ok");

is($subs[0]->arg1, $subscr->arg1, "OK subscription");

$subscr->delete;
