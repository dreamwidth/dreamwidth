# t/comment.t
#
# Test LJ::Comment.
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

use Test::More tests => 405;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Protocol;
use LJ::Comment;
use LJ::Talk;
use LJ::Test qw(memcache_stress temp_user);
use POSIX ();

my $u = temp_user();

sub run_tests {
    # constructor tests
    {
        my $c;

        $c = eval { LJ::Comment->new({}, jtalkid => 1) };
        like($@, qr/invalid journalid/, "invalid journalid parameter");

        $c = eval { LJ::Comment->new(0, jtalkid => 1) };
        like($@, qr/invalid journalid/, "invalid user from userid");

        $c = eval { LJ::Comment->new($u, jtalkid => 1, 'foo') };
        like($@, qr/wrong number/, "wrong number of arguments");

        $c = eval { LJ::Comment->new($u, jtalkid => undef) };
        like($@, qr/need to supply jtalkid/, "need to supply jtalkid");

        $c = eval { LJ::Comment->new($u, jtalkid => 1, foo => 1, bar => 2) };
        like($@, qr/wrong number/, "wrong number of arguments (unknown parameters)");
    }

    # post a comment
    {
        my $e1 = $u->t_post_fake_entry;
        ok($e1, "Posted entry");

        my $c1 = $e1->t_enter_comment;
        ok($c1, "Posted comment");

        # check that the comment happened in the last 60 seconds
        my $c1time = $c1->unixtime;
        ok($c1time, "Got comment time");
        ok(POSIX::abs($c1time - time()) < 60, "Comment happened in last minute");
    }

    # test prop setting/modifying/deleting
    {
        my $e2 = $u->t_post_fake_entry;
        my $c2 = $e2->t_enter_comment;

        # set a prop once, then re-set its value again
        my $jtalkid = $c2->jtalkid;

        # FIXME the whole idea of using undef as one of the loop values seem to make the code
        # more complex, check if this can be changed
        foreach my $propval (0,1,undef,1) {
            # re-instantiate if we've blown $c2 away
            $c2 ||= LJ::Comment->new($u, jtalkid => $jtalkid);

            my $inserted = 0;
            $LJ::_T_COMMENT_SET_PROPS_INSERT = sub { $inserted++ };
            my $deleted = 0;
            $LJ::_T_COMMENT_SET_PROPS_DELETE = sub { $deleted++ };

            $c2->set_prop('opt_preformatted', $propval);

            if (defined $propval) {
                ok($inserted == 1 && $deleted == 0, "$propval: Inserted talkprop row prop-erly");
            } else {
                ok($deleted == 1 && $inserted == 0, "undef: Deleted talkprop row prop-erly");
            }

            is($c2->prop('opt_preformatted'),  $propval, (defined $propval ? $propval : 'undef') . ": Set prop and read back via ->prop");
            is($c2->props->{opt_preformatted}, $propval, (defined $propval ? $propval : 'undef') . ": Set prop and read back via ->props");

            # clear the singleton and load again
            LJ::Comment->reset_singletons;
            my $loaded = 0;
            $LJ::_T_GET_TALK_PROPS2_MEMCACHE = sub { $loaded++ };

            my $c2_new = LJ::Comment->new($u, jtalkid => $jtalkid);
            my $propval = $c2_new->prop('opt_preformatted');
            ok($loaded == 1, (defined $propval ? $propval : 'undef') . ", Re-instantiated comment and re-loaded prop");
            ok($c2_new != $c2, (defined $propval ? $propval : 'undef') . ", Re-instantiated comment and re-loaded prop");
        }

        # test raw prop setting/modifying
        {
            # re-instantiate if we've blown $c2 away
            $c2 ||= LJ::Comment->new($u, jtalkid => $jtalkid);

            my $inserted = 0;
            $LJ::_T_COMMENT_SET_PROPS_INSERT = sub { $inserted++ };
            my $deleted = 0;
            $LJ::_T_COMMENT_SET_PROPS_DELETE = sub { $deleted++ };

            $c2->set_prop_raw('edit_time', "UNIX_TIMESTAMP()");

            ok($inserted == 1 && $deleted == 0, "Inserted raw talkprop row prop-erly");

            ok($c2->prop('edit_time') =~ /^\d+$/, "Set raw prop and read back via ->prop");
            ok($c2->props->{edit_time} =~ /^\d+$/ , "Set raw prop and read back via ->props");

            # clear the singleton and load again
            LJ::Comment->reset_singletons;
            my $loaded = 0;
            $LJ::_T_GET_TALK_PROPS2_MEMCACHE = sub { $loaded++ };

            my $c2_new = LJ::Comment->new($u, jtalkid => $jtalkid);
            my $propval = $c2_new->prop('edit_time');
            ok($loaded == 1 && $c2_new != $c2 && $propval == $propval, "Re-instantiated comment and re-loaded raw prop");
        }

        # test prop multi-setting/modifying/deleting
        # test prop setting/modifying/deleting
        {
            my $inserted = 0;
            $LJ::_T_COMMENT_SET_PROPS_INSERT = sub { $inserted++ };
            my $deleted = 0;
            $LJ::_T_COMMENT_SET_PROPS_DELETE = sub { $deleted++ };
            my $queried = 0;
            $LJ::_T_GET_TALK_PROPS2_MEMCACHE = sub { $queried++ };

            { # both inserts
                my $e3 = $u->t_post_fake_entry;
                my $c3 = $e3->t_enter_comment;

                $c3->set_props('opt_preformatted' => 1, 'picture_keyword' => 2);
                ok($c3->prop('opt_preformatted') == 1 && $c3->prop('picture_keyword') == 2 &&
                   $inserted == 1 && $deleted == 0 && $queried == 1,
                   "Set 2 props and read back");
            }

            ($inserted, $deleted, $queried) = (0,0,0);

            { # mixed
                my $e4 = $u->t_post_fake_entry;
                my $c4 = $e4->t_enter_comment;

                $c4->set_props('opt_preformatted' => undef, 'picture_keyword' => 2);
                ok(!defined( $c4->prop('opt_preformatted') ) && $c4->prop('picture_keyword') == 2 &&
                   $inserted == 1 && $deleted == 1 && $queried == 1,
                   "Set 1 prop, deleted 1, and read back");
            }

            ($inserted, $deleted, $queried) = (0,0,0);

            { # deletes
                my $e5 = $u->t_post_fake_entry;
                my $c5 = $e5->t_enter_comment;

                $c5->set_props('opt_preformatted' => undef, 'picture_keyword' => undef);
                ok(!defined( $c5->prop('opt_preformatted') ) && !defined( $c5->prop('picture_keyword') ) &&
                   $inserted == 0 && $deleted == 1 && $queried == 1,
                   "Set 1 prop, deleted 1, and read back");
            }

            ($inserted, $deleted, $queried) = (0,0,0);

            { # raw
                my $e6 = $u->t_post_fake_entry;
                my $c6 = $e6->t_enter_comment;

                $c6->set_props_raw('edit_time' => "UNIX_TIMESTAMP()", 'opt_preformatted' => 1);
                ok($c6->prop('opt_preformatted') == 1 && $c6->prop('edit_time') =~ /^\d+$/ &&
                   $inserted == 1 && $deleted == 0 && $queried == 1,
                   "Set 2 raw props and read back");
            }
        }
    }

    # post a tree of comments
    {

        # step counter so we can test multiple legacy API interactions
        foreach my $step (0..2) {

            my $entry = $u->t_post_fake_entry;

            # entry
            # - child 0
            # - child 1
            #   + child 1.1
            # - child 2
            #   + child 2.1
            #   + child 2.2
            # - child 3
            #   + child 3.1
            #   + child 3.2
            #   + child 3.3
            # - child 4
            #   + child 4.1
            #   + child 4.2
            #   + child 4.3
            #   + child 4.4
            # - child 5
            #   + child 5.1
            #   + child 5.2
            #   + child 5.3
            #   + child 5.4
            #   + child 5.5

            my @tree = (); # [ child => [ sub_children ]

            # create 5 comments on this entry
            foreach my $top_reply_ct (0..5) {
                my $c = $entry->t_enter_comment;

                my $curr = [ $c => [] ];
                push @tree, $curr;

                # now make 5 replies to each comment, except for the first
                foreach my $reply_ct (1..$top_reply_ct) {
                    last if $top_reply_ct == 0;

                    my $child = $c->t_reply;
                    $child->set_prop('opt_preformatted', 1);
                    push @{$curr->[1]}, $child;
                }
            }

            # are the first-level children created properly?
            ok(@tree == 6, "$step: Created 6 child comments");

            # how about subchildren?
            my %want = map { $_ => 1 } 0..5;
            delete $want{scalar @{$_->[1]} } foreach @tree;
            ok(! %want, "$step: Created 0..5 sub-child comments");


            # test accesses to ->children methods in cases where legacy APIs are also called
            my %access_ct = ();
            $LJ::_T_GET_TALK_DATA_MEMCACHE   = sub { $access_ct{data}++  };
            $LJ::_T_GET_TALK_TEXT2_MEMCACHE  = sub { $access_ct{text}++  };
            $LJ::_T_GET_TALK_PROPS2_MEMCACHE = sub { $access_ct{props}++ };

            # 0: straight call to ->children
            # 1: get_talk_data call
            # 2: $entry->comment_list call
            # 3: load_comments call
            LJ::Talk::get_talk_data($u, 'L', $entry->jitemid)        if $step == 1;
            $entry->comment_list                                     if $step == 2;
            LJ::Talk::load_comments($u, undef, 'L', $entry->jitemid) if $step == 3;

            %want = map { $_ => 1 } 0..5;
            foreach my $parent (map { $_->[0] } @tree) {

                my @children = $parent->children;
                delete $want{scalar @children};

                # now access text and props
                # FIXME: should test case of legacy prop/text access, then object method
                $parent->props;
                $parent->body_raw;

                foreach my $child (@children) {
                    $child->props;
                    $child->subject_raw;
                }
            }
            ok( ! %want, "$step: Retrieved 0..5 sub-children LJ::Comment objects");
            ok( $access_ct{data} == 1, "$step: Only one talk data access with legacy interaction");
            ok( $access_ct{text} == 1, "$step: Only one text data access with legacy interaction");
            ok( $access_ct{props} == 1, "$step: Only one prop data access with legacy interaction");

            # Add to the tree:
            # - child 6
            #   + child 6.1
            #     + child 6.1.1
            #       + child 6.1.1.1
            my $comment = $entry->t_enter_comment;
            my $curr = [ $comment => [] ];
            push @tree, $curr;
            foreach ( 1..3 ) {
                $comment = $comment->t_reply;
                push @{$curr->[1]}, $comment;
            }

            # look up root
            foreach my $parent (map { $_->[0] } @tree) {
                ok ( $parent->threadrootid eq $parent->jtalkid, "Comment depth 1: this is the thread root" );

                my @children = $parent->children;
                foreach my $child ( @children ) {
                    ok ( $child->parenttalkid == $child->threadrootid, "Comment depth 2: thread root and parent are equivalent." );

                    my $descendant = $child;
                    my $depth = 2;
                    foreach ( $descendant->children ) {
                        ok ( $child->parenttalkid == $descendant->threadrootid, "Comment depth $depth: thread root is no longer directly linked to this comment." );

                        $depth++;
                        $descendant = $_;
                    }
                }
            }
        }
    }

    # test editing of comment text
    {
        my $e = $u->t_post_fake_entry;
        my $c = $e->t_enter_comment;

        my $jtalkid     = $c->jtalkid;
        my $old_subject = $c->subject_raw;
        my $old_body    = $c->body_raw;

        {
            my $new_subject = LJ::rand_chars(25);
            my $new_body    = LJ::rand_chars(500);
            $c->set_subject($new_subject);
            ok($c->subject_raw eq $new_subject && $c->body_raw eq $old_body, "Set subject okay");

            $c->set_body($new_body);
            ok($c->subject_raw eq $new_subject && $c->body_raw eq $new_body, "Set body okay");

            # clear out and check memcache
            LJ::Comment->reset_singletons;

            $c = LJ::Comment->new($u, jtalkid => $jtalkid);
            ok($c->subject_raw eq $new_subject && $c->body_raw eq $new_body, "Read subject and body back from memcache");
        }

        {
            my $new_subject = LJ::rand_chars(25);
            my $new_body    = LJ::rand_chars(500);

            $c->set_subject_and_body($new_subject, $new_body);
            ok($c->subject_raw eq $new_subject && $c->body_raw eq $new_body, "Set subject and body at once");

            # clear out and check memcache
            LJ::Comment->reset_singletons;

            $c = LJ::Comment->new($u, jtalkid => $jtalkid);
            ok($c->subject_raw eq $new_subject && $c->body_raw eq $new_body, "Read subject and body back from memcache");

        }

        # test setting of subejct / body with unknown8bit set
        {
            $c->set_prop('unknown8bit', 1);

            eval { $c->set_subject($old_subject) };
            ok($@ =~ 'unknown8bit', "Can't set unknown8bit without subject / body");

            eval { $c->set_subject_and_body($old_subject, $old_body) };
            ok(! $@ && $c->subject_raw eq $old_subject && $c->body_raw eq $old_body, "Able to set unknown8bit with subject and body");
            ok($c->prop('unknown8bit') == 0, "unknown8bit prop unset");
        }
    }
}

memcache_stress {
    run_tests();
};

1;

