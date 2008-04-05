# -*-perl-*-

use strict;
use Test::More tests => 7;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

my $u1 = temp_user();
my $u2 = temp_user();

my %got_email = ();   # userid -> received email

local $LJ::_T_EMAIL_NOTIFICATION = sub {
    my ($u, $body) = @_;
    $got_email{$u->userid}++;
    return 1;
};

my $proc_events = sub {
    %got_email = ();
    LJ::Event->process_fired_events;
};

my $got_notified = sub {
    my $u = shift;
    $proc_events->();
    return $got_email{$u->{userid}};
};


sub run_tests {
    # subscribe $u1 to receive all new comments on an entry by $u1,
    # then subscribe $u1 to receive all new comments on a thread under
    # that entry. Then, make sure $u1 only receives one notification
    # for each new comment on that thread instead of two.

    # post an entry on $u2
    ok($u1 && $u2, "Got users");
    my $entry = $u2->t_post_fake_entry;
    ok($entry, "Posted fake entry");

    # subscribe $u1 to new comments on this entry
    my $subscr1 = $u1->subscribe(
                                 journal => $u2,
                                 arg1    => $entry->ditemid,
                                 method  => "Email",
                                 event   => "JournalNewComment",
                                 );
    ok($subscr1, "Subscribed u1 to new comments on entry");

    # make a comment and make sure $u1 gets notified
    my $c_parent = $entry->t_enter_comment(u => $u2);
    ok($c_parent, "Posted comment");

    my $notifycount = $got_notified->($u1);
    is($notifycount, 1, "Got notified once");

    # subscribe u1 to new comments on this thread
    my $subscr2 = $u1->subscribe(
                                 journal => $u2,
                                 arg1    => $entry->ditemid,
                                 arg2    => $c_parent->jtalkid,
                                 method  => "Inbox",
                                 event   => "JournalNewComment",
                                 );
    my $subscr3 = $u1->subscribe(
                                 journal => $u2,
                                 arg1    => $entry->ditemid,
                                 arg2    => $c_parent->jtalkid,
                                 method  => "Email",
                                 event   => "JournalNewComment",
                                 );

    ok($subscr2, "Subscribed u1 to new comments on thread");

    # post a reply to the thread and make sure $u1 only got notified once
    $c_parent->t_reply(u => $u2);

    $notifycount = $got_notified->($u1);
    is($notifycount, 1, "Got notified only once");

    $subscr1->delete;
    $subscr2->delete;
}

run_tests();
