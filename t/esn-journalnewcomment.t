# t/esn-journalnewcomment.t
#
# Test notifications for new journal comments.
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

use Test::More tests => 39;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Protocol;

use LJ::Event;
use LJ::Talk;
use LJ::Test qw(memcache_stress temp_user);
use FindBin qw($Bin);

# we want to test eight major cases here, matching and not matching for
# four types of subscriptions, all of subscr etypeid = JournalNewComment
#
#          jid   sarg1   sarg2   meaning
#    S1:     n       0       0   all new comments in journal 'n' (subject to security)
#    S2:     n ditemid       0   all new comments on post (n,ditemid)
#    S3:     n ditemid jtalkid   all new comments UNDER comment n/jtalkid (in ditemid)
#    S4:     0       0       0   all new comments from any journal you watch
#    -- NOTE: This test is disabled unless JournalNewComment allows it

# we also want to test for matching and not matching cases for JournalNewComment::TopLevel
# a subclass of JournalNewComment

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
    my $othercomment;

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

    # make sure we didn't get notification
    $email = $got_notified->($u1);
    ok(! $email, "got no email");

    # S1 failing case, posting to u2, due to security
    my $u2e2f = eval { $u2->t_post_fake_entry(security => "friends") };
    ok($u2e2f, "did a post");
    is($u2e2f->security, "usemask", "is actually friends only");

    # post a comment on it
    $comment = $u2e2f->t_enter_comment;
    ok($comment, "got jtalkid");

    # make sure we didn't get notification
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

    # entry gets locked
    $u2e1->{security} = "friends";
    ok($u2e1, "first entry locked");

    # u2 comments on their own entry
    $othercomment = $u2e1->t_enter_comment;
    ok($othercomment, "comment added to locked entry");

    # u1 can't see and doesn't get notified
    $email = $got_notified->($u1);
    ok(!$email, "didn't get comment notification on locked post");

    $u2e1->{security} = "public";

    $subsc->delete;

    ######## S3 (watching a thread)

    # make sure we can track threads
    $LJ::CAP{$_}->{track_thread} = 1 foreach (0..15);

    # subscribe to replies to a thread
    $subsc = $u1->subscribe(
                            event   => "JournalNewComment",
                            method  => "Email",
                            journal => $u2,
                            arg1    => $u2e3->ditemid,
                            arg2    => $comment->jtalkid,
                            );
    ok($subsc, "Subscribed");

    # post a reply to the comment from the earlier test
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

    $LJ::CAP{$_}->{track_thread} = 0 foreach (0..15);
    $subsc->delete;

    if ( ( LJ::Event::JournalNewComment->zero_journalid_subs_means // "" ) eq "friends") {
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
                $u1->remove_edge( $u2, watch => { nonotify => 1 } );

            } elsif ($pass == 2) {
                $email = $got_email{$u1->{userid}};
                ok(! $email, "didn't get wildcard notification");

                # add the friend back
                $u1->add_edge( $u2, watch => { nonotify => 1 }); # make u1 watch u2
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


    # LJ::Event::JournalNewComment::TopLevel
    my $u2e5 = eval { $u2->t_post_fake_entry };

    # subscribe to replies to a thread
    $subsc = $u1->subscribe(
                            event   => "JournalNewComment::TopLevel",
                            method  => "Email",
                            journal => $u2,
                            arg1    => $u2e5->ditemid,
                            );
    ok( $subsc, "Subscribed" );

    # post a top-level comment
    $comment = $u2e5->t_enter_comment;
    ok( $comment, "Posted comment" );

    $proc_events->();

    $email = $got_email{$u1->{userid}};
    ok( $email, "Got notified" );

    $email = $got_email{$u2->{userid}};
    ok( ! $email, "Unsubscribed watcher not notified" );

    # reply to a comment on this entry, make sure we're not notified
    $reply = $comment->t_reply;
    ok( $reply, "Posted reply" );

    $email = $got_notified->( $u1 );
    ok( ! $email, "didn't get notified" );

    $subsc->delete;

    my $u2e6 = eval { $u2->t_post_fake_entry };
    $subsc = $u1->subscribe(
                            event   => "JournalNewComment",
                            method  => "Email",
                            journal => $u2,
                            arg1    => $u2e6->ditemid,
                            );

    my $subsc2 = $u1->subscribe(
                    event  => "JournalNewComment::TopLevel",
                    method  => "Email",
                    journal => $u2,
                    arg1    => $u2e6->ditemid,
                );
    ok( $subsc2, "Subscribed to new top-level comments on this journal" );

    $comment = $u2e6->t_enter_comment( u => $u2 );
    ok( $comment, "Posted comment" );

    $proc_events->();
    is( $got_email{$u1->userid}, 1, "No duplicate emails");

    $subsc->delete;
    $subsc2->delete;

});

sub test_esn_flow {
    my $cv = shift;
    my $u1 = temp_user();
    my $u2 = temp_user();
    $u1->add_edge( $u2, watch => { nonotify => 1 }); # make u1 watch u2
    $cv->($u1, $u2);
}

1;

