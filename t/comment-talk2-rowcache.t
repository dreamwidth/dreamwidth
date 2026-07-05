# t/comment-talk2-rowcache.t
#
# Exercise the comment-data caches (the packed talk2 blob from get_talk_data and
# the per-comment talk2row entries from get_talk2_row_multi) across a full
# read/write lifecycle, asserting that the database is only read on a cache miss,
# that memcache serves warm reads, and that writes clear the right keys.
#
# Also guards the change that get_talk_data no longer eagerly populates talk2row
# (that is done lazily by get_talk2_row_multi).
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
use LJ::Test qw( temp_user );

# We need memcache ON to tell cache hits from DB reads, so install the in-memory
# fake client directly (rather than memcache_stress, which also runs cache-off).
my $fake = LJ::Test::FakeMemCache->new;
@LJ::MEMCACHE_SERVERS = ("fake");
LJ::MemCache::set_memcache($fake);

# count DB reads on each comment-loading path (hooks live in LJ::Talk)
# reset before each measured step; explicit 0s so "no read" reads as 0, not undef
my %db = ( data => 0, row => 0 );
$LJ::_T_GET_TALK_DATA_DB = sub { $db{data}++ };
$LJ::_T_GET_TALK2_ROW_DB = sub { $db{row}++ };

my $u       = temp_user();
my $entry   = $u->t_post_fake_entry;
my $c1      = $entry->t_enter_comment;    # top-level
my $c2      = $c1->t_reply;               # reply to c1
my $c1id    = $c1->jtalkid;
my $c2id    = $c2->jtalkid;
my $jid     = $u->userid;
my $jitemid = $entry->jitemid;

my $blobkey = [ $jid, "talk2:$jid:L:$jitemid" ];
my $rowkey  = sub { [ $jid, "talk2row:$jid:$_[0]" ] };

# start from a clean cache
LJ::MemCache::delete($blobkey);
LJ::Talk::invalidate_talk2row_memcache( $jid, $c1id, $c2id );

# --- reads: DB on the cold miss, memcache on the warm hit ---

# cold: one DB read, blob cached, per-comment rows NOT eagerly cached
%db = ( data => 0, row => 0 );
my $data = LJ::Talk::get_talk_data( $u, 'L', $jitemid );
is( $db{data}, 1, "cold get_talk_data does one DB read" );
ok( LJ::MemCache::get($blobkey), "get_talk_data caches the talk2 blob" );
ok( !LJ::MemCache::get( $rowkey->($c2id) ),
    "get_talk_data does not eagerly cache per-comment rows" );
ok( $data->{$c1id} && $data->{$c2id}, "both comments present" );
is( $data->{$c2id}->{parenttalkid}, $c1id, "threading is correct" );

# warm: no DB, identical comment set
%db = ( data => 0, row => 0 );
my $warm = LJ::Talk::get_talk_data( $u, 'L', $jitemid );
is( $db{data}, 0, "warm get_talk_data serves from memcache (no DB)" );
is_deeply(
    [ sort { $a <=> $b } keys %$warm ],
    [ sort { $a <=> $b } keys %$data ],
    "warm read returns the same comment set"
);

# per-comment rows: DB on the cold miss (batched), memcache on the warm hit
%db = ( data => 0, row => 0 );
my @rows = LJ::Talk::get_talk2_row_multi( [ $u, $c1id ], [ $u, $c2id ] );
is( $db{row}, 1, "cold get_talk2_row_multi does one batched DB read" );
ok( LJ::MemCache::get( $rowkey->($c2id) ), "rows are cached after the lazy load" );
is( $rows[1]->{parenttalkid}, $c1id, "loaded row threading is correct" );

%db   = ( data => 0, row => 0 );
@rows = LJ::Talk::get_talk2_row_multi( [ $u, $c1id ], [ $u, $c2id ] );
is( $db{row}, 0, "warm get_talk2_row_multi serves from memcache (no DB)" );

# --- writes: the right things get cleared ---

# posting a comment clears the blob but leaves unrelated per-comment rows
my $c3   = $entry->t_enter_comment;
my $c3id = $c3->jtalkid;
ok( !LJ::MemCache::get($blobkey),          "posting a comment clears the talk2 blob" );
ok( LJ::MemCache::get( $rowkey->($c2id) ), "posting a comment leaves other comments' rows intact" );

%db = ( data => 0, row => 0 );
my $after_post = LJ::Talk::get_talk_data( $u, 'L', $jitemid );
is( $db{data}, 1, "read after a post regenerates from DB" );
ok( $after_post->{$c3id}, "regenerated data includes the new comment" );

# deleting a comment clears the blob and that comment's own row
$c2->delete;
ok( !LJ::MemCache::get($blobkey),           "deleting a comment clears the talk2 blob" );
ok( !LJ::MemCache::get( $rowkey->($c2id) ), "deleting a comment clears its own row" );

%db = ( data => 0, row => 0 );
my $after_del = LJ::Talk::get_talk_data( $u, 'L', $jitemid );
is( $db{data},                    1,   "read after a delete regenerates from DB" );
is( $after_del->{$c2id}->{state}, 'D', "deleted comment is marked deleted after regen" );

done_testing();
