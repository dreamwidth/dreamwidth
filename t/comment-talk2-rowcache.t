# t/comment-talk2-rowcache.t
#
# get_talk_data no longer eagerly populates the per-comment talk2row cache;
# that is done lazily by get_talk2_row_multi. Verify comments still load
# correctly and consistently from a cold cache through both paths.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Comment;
use LJ::Talk;
use LJ::Test qw( memcache_stress temp_user );

my $u = temp_user();

my $run = sub {
    my $entry = $u->t_post_fake_entry;
    my $c1    = $entry->t_enter_comment;    # top-level
    my $c2    = $c1->t_reply;               # reply to c1

    my $jid     = $u->userid;
    my $jitemid = $entry->jitemid;

    # cold: drop the packed blob and both per-comment rows, so get_talk_data has
    # to regenerate (the path that no longer pre-warms talk2row) and the rows
    # have to load lazily.
    LJ::MemCache::delete( [ $jid, "talk2:$jid:L:$jitemid" ] );
    LJ::Talk::invalidate_talk2row_memcache( $jid, $c1->jtalkid, $c2->jtalkid );

    # get_talk_data returns the correct comment set from a cold cache
    my $data = LJ::Talk::get_talk_data( $u, 'L', $jitemid );
    ok(
        $data->{ $c1->jtalkid } && $data->{ $c2->jtalkid },
        "both comments present in get_talk_data"
    );
    is( $data->{ $c1->jtalkid }->{parenttalkid}, 0,            "top-level comment has parent 0" );
    is( $data->{ $c2->jtalkid }->{parenttalkid}, $c1->jtalkid, "reply points at its parent" );
    is( $data->{ $c2->jtalkid }->{posterid}, $c2->posterid,
        "get_talk_data poster matches comment" );
    is( $data->{ $c2->jtalkid }->{state}, "A", "reply state is approved" );

    # the rows load correctly and consistently through the lazy path (from the
    # per-row cache if warm, otherwise the batched DB fallback)
    my @rows = LJ::Talk::get_talk2_row_multi( [ $u, $c1->jtalkid ], [ $u, $c2->jtalkid ] );
    is( $rows[0]->{parenttalkid}, 0,            "row: top-level parent is 0" );
    is( $rows[1]->{parenttalkid}, $c1->jtalkid, "row: reply parent is correct" );
    is(
        $rows[1]->{posterid},
        $data->{ $c2->jtalkid }->{posterid},
        "row poster agrees with get_talk_data"
    );
    is( $rows[1]->{state}, "A", "row: reply state is correct" );
};

memcache_stress { $run->() };

done_testing();
