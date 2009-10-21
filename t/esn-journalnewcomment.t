# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'ljprotocol.pl';

use LJ::Event;
use LJ::Talk;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

#plan tests => ;
plan skip_all => 'Fix this test!';

# we want to test eight major cases here, matching and not matching for
# four types of subscriptions, all of subscr etypeid = JournalNewComment
#
#          jid   sarg1   sarg2   meaning
#    S1:     n       0       0   all new comments in journal 'n' (subject to security)
#    S2:     n ditemid       0   all new comments on post (n,ditemid)
#    S3:     n ditemid jtalkid   all new comments UNDER comment n/jtalkid (in ditemid)
#    S4:     0       0       0   all new comments from any journal you watch
#    -- NOTE: This test is disabled unless JournalNewComment allows it

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

# testing case S1 above:
test_esn_flow(sub {
    my ($u1, $u2) = @_;
    my $email;
    my $comment;

    # clear subs
    $_->delete foreach $u1->subscriptions;
    $_->delete foreach $u2->subscriptions;

    # subscribe $u1 to all posts on $u2
    my $subsc = $u1->subscribe(
                               event   => "JournalNewComment",
                               method  => "Email",
                               journal => $u2,
                               );
    ok($subsc, "made S1 subscription");

    # post an entry in $u2
    my $u2e1 = eval { $u2->t_post_fake_entry };
    ok($u2e1, "made a post");
    is($@, "", "no errors");

    # $u1 leave a comment on $u2
    $comment = $u2e1->t_enter_comment;
    ok($comment, "left a comment");

    # make sure we got notification
    $email = $got_notified->($u1);
    ok($email, "got the email");

    # S1 failing case:
    # post an entry on $u1, where nobody's subscribed
    my $u1e1 = eval { $u1->t_post_fake_entry };
    ok($u1e1, "did a post");

    # post a comment on it
    $comment = $u1e1->t_enter_comment;
    ok($comment, "left comment");

    # make sure we got notification
    $email = $got_notified->($u1);
    ok(! $email, "got no email");

    # S1 failing case, posting to u2, due to security
    my $u2e2f = eval { $u2->t_post_fake_entry(security => "friends") };
    ok($u2e2f, "did a post");
    is($u2e2f->security, "usemask", "is actually friends only");

    # post a comment on it
    $comment = $u2e2f->t_enter_comment;
    ok($comment, "got jtalkid");

    # make sure we got notification
    $email = $got_notified->($u1);
    ok(! $email, "got no email, due to security (u2 doesn't trust u1)");

    ok($subsc->delete, "Deleted subscription");

    ###### S2:
    # subscribe $u1 to all comments on u2e1
    $subsc = $u1->subscribe(
                            event   => "JournalNewComment",
                            method  => "Email",
                            journal => $u2,
                            arg1    => $u2e1->ditemid,
                            );
    ok($subsc, "made S2 subscription");

    # post a comment on u2e1
    $comment = $u2e1->t_enter_comment;
    ok($comment, "got jtalkid");

    $email = $got_notified->($u1);
    ok($email, "Got comment notification");

    # post another entry on u2
    my $u2e3 = eval { $u2->t_post_fake_entry };
    ok($u2e3, "did a post");

    # post a comment that $subsc won't match
    $comment = $u2e3->t_enter_comment(u => $u2);
    ok($comment, "Posted comment");

    $email = $got_notified->($u1);
    ok(!$email, "didn't get comment notification on unrelated post");

    $subsc->delete;

    ######## S3 (watching a thread)

    # subscribe to replies to a thread
    $subsc = $u1->subscribe(
                            event   => "JournalNewComment",
                            method  => "Email",
                            journal => $u2,
                            arg1    => $u2e3->ditemid,
                            arg2    => $comment->jtalkid,
                            );
    ok($subsc, "Subscribed");

    # post a reply to a comment
    my $reply = $comment->t_reply(u => $u2);
    ok($reply, "Got reply");

    $proc_events->();

    $email = $got_email{$u1->{userid}};
    ok($email, "Got notified");

    $email = $got_email{$u2->{userid}};
    ok(! $email, "Unsubscribed watcher not notified");

    # post a new comment on this entry, make sure not notified
    my $comment2 = $u2e3->t_enter_comment;
    ok($comment2, "Posted comment");

    $email = $got_notified->($u1);
    ok(! $email, "didn't get notified");

    # post a reply to a different thread and make sure not notified
    my $reply2 = $comment2->t_reply;
    ok($reply2, "Posted reply");

    $email = $got_notified->($u1);
    ok(! $email, "didn't get notified");

    $subsc->delete;

    if (LJ::Event::JournalNewComment->zero_journalid_subs_means eq "friends") {
        ####### S4 (watching new comments on all friends' journals)

        $subsc = $u1->subscribe(
                                event   => "JournalNewComment",
                                method  => "Email",
                                );
        ok($subsc, "made S4 wildcard subscription");

        my $u2e4 = eval { $u2->t_post_fake_entry };
        ok($u2e4, "Got entry");

        for my $pass (1..2) {
            my $u2c1 = eval { $u2e4->t_enter_comment };
            ok($u2c1, "Posted comment");

            $proc_events->();

            if ($pass == 1) {
                $email = $got_email{$u1->{userid}};
                ok($email, "Got wildcard notification");

                $email = $got_email{$u2->{userid}};
                ok(! $email, "Non-subscribed user did not get notification");

                # remove the friend
                LJ::remove_friend($u1, $u2);

            } elsif ($pass == 2) {
                $email = $got_email{$u1->{userid}};
                ok(! $email, "didn't get wildcard notification");

                # add the friend back
                LJ::add_friend($u1, $u2); # make u1 friend u2
            }
        }

        # leave some comment on u1, make sure no notification received
        my $u1e2 = eval { $u1->t_post_fake_entry };
        ok($u1e2, "Posted entry");

        my $u1c1 = eval { $u1e2->t_enter_comment };
        ok($u1c1, "Got comment");

        $email = $got_notified->($u1);
        ok(! $email, "Did not receive notification");
        $subsc->delete;
    }

});

sub test_esn_flow {
    my $cv = shift;
    my $u1 = temp_user();
    my $u2 = temp_user();
    LJ::add_friend($u1, $u2); # make u1 friend u2
    $cv->($u1, $u2);
}

1;

