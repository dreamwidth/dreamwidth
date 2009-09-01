# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'ljprotocol.pl';

BEGIN { $LJ::HOME = $ENV{LJHOME}; }
use LJ::Event;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

# plan tests => ;
plan skip_all => 'Fix this test!';

# so this event firing isn't disabled:
local $LJ::_T_FIRE_USERNEWENTRY = 1;

# we want to test four major cases here, matching and not matching for
# two types of subscriptions, all of subscr etypeid = JournalNewEntry
#
#          jid   sarg1   sarg2   meaning
#    S1:     n       0       0   all new posts made by user 'n' (subject to security)
#    S2:     0       0       0   all new posts made by friends  (test security)
#    --- NOTE: S2 is currently disabled
#

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


my $mem_round = 0;
my $s1s2;

# testing case S1 above:
memcache_stress(sub {
    $mem_round++;

    test_esn_flow(sub {
        my ($u1, $u2, $ucomm) = @_;

        # subscribe $u1 to all posts by $u2
        my $subsc = $u1->subscribe(
                                   event   => "UserNewEntry",
                                   method  => "Email",
                                   journal => $u2,
                                   );

        ok($subsc, "made S1 subscription");

        $s1s2 = "S1";
        test_post($u1, $u2, $ucomm);

        ok($subsc->delete, "Deleted subscription");

        ###### S2:
        if (LJ::Event::JournalNewEntry->zero_journalid_subs_means eq "friends") {
            # subscribe $u1 to all comments on all friends journals
            # subscribe $u1 to all posts on $u2
            my $subsc = $u1->subscribe(
                                       event   => "JournalNewEntry",
                                       method  => "Email",
                                       );

            ok($subsc, "made S2 subscription");

            $s1s2 = "S2";
            test_post($u1, $u2, $ucomm);

            # remove $u2 from $u1's friends list, post in $u2 and make sure $u1 isn't notified
            LJ::remove_friend($u1, $u2); # make u1 friend u2
            $u2->t_post_fake_entry;
            my $email = $got_notified->($u1);
            ok(! $email, "u1 did not get notified because u2 is no longer his friend");
            ok($subsc->delete, "Deleted subscription");
        }

    });
});

# post an entry in $u2, by $u2 and make sure $u1 gets notified
# post an entry in $u1, by $u2 and make sure $u1 doesn't get notified
# post a friends-only entry in $u2, by $u2 and make sure $u1 doesn't get notified
# post an entry in $ucomm, by $u2 and make sure $u1 gets notified
# post an entry in $u1, by $ucomm and make sure $u1 doesn't get notified
# post a friends-only entry in $ucomm, by $u2 and make sure $u1 doesn't get notified
sub test_post {
    my ($u1, $u2, $ucomm) = @_;
    my $email;

    LJ::set_rel($ucomm, $u2, "P");
    foreach my $usejournal (0..1) {
        my %opts = $usejournal ? ( usejournal => $ucomm->{user} ) : ();
        my $suffix = $usejournal ? " in comm" : "";

        my $state = "(state: mem=$mem_round,s1s2=$s1s2,usejournal=$usejournal)";

        # post an entry in $u2
        my $u2e1 = eval { $u2->t_post_fake_entry(%opts) };
        ok($u2e1, "made a post$suffix");
        is($@, "", "no errors");

        # S1 failing case:
        # post an entry on $u1, where nobody's subscribed
        my $u1e1 = eval { $u1->t_post_fake_entry(%opts) };
        ok($u1e1, "did a post$suffix");

        # make sure we did not get notification
        $email = $got_notified->($u1);
        ok(! $email, "got no email");

        # S1 failing case, posting to u2, due to security
        my $u2e2f = eval { $u2->t_post_fake_entry(%opts, security => "friends") };
        ok($u2e2f, "did a post$suffix");
        is($u2e2f->security, "usemask", "is actually friends only");

        # make sure we didn't get notification
        $email = $got_notified->($u1);
        ok(! $email, "got no email, due to security (u2 doesn't trust u1)");
    }
}


sub test_esn_flow {
    my $cv = shift;
    my $u1 = temp_user();
    my $u2 = temp_user();

    # need a community for $u1 and $u2 to play in
    my $ucomm = temp_user();
    LJ::update_user($ucomm, { journaltype => 'C' });

    LJ::add_friend($u1, $u2); # make u1 friend u2
    $cv->($u1, $u2, $ucomm);
}

1;

