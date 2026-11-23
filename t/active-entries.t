# t/active-entries.t
#
# Tests $u->active_entries: the 10 most-recently-commented entries, newest
# first, deduped, ignoring deleted and screened comments. Runs under MySQL 8's
# default ONLY_FULL_GROUP_BY.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Comment;
use LJ::Talk;
use LJ::Test qw( temp_user );
use DW::Logic::LogItems;

# active_entries reads and writes memcache; use the in-memory fake so we control it.
my $fake = LJ::Test::FakeMemCache->new;
@LJ::MEMCACHE_SERVERS = ("fake");
LJ::MemCache::set_memcache($fake);

my $u = temp_user();

# Twelve entries, each with one approved comment, posted oldest-to-newest so that
# jtalkid (hence comment recency) ascends with the array index. Unique subjects
# dodge postevent's duplicate-submission protection.
my @e = map { $u->t_post_fake_entry( subject => "active-entries $_" ) } 0 .. 11;
$e[$_]->t_enter_comment for 0 .. 11;

# A repeated comment on e5 makes it the most recently commented entry; it must
# still appear exactly once.
$e[5]->t_enter_comment;

# The two newest comments are screened and deleted respectively, on entries that
# are otherwise uncommented; neither entry may appear in the result.
my $screened_entry = $u->t_post_fake_entry( subject => "screened" );
$screened_entry->t_enter_comment( state => 'S' );

my $deleted_entry = $u->t_post_fake_entry( subject => "deleted" );
$deleted_entry->t_enter_comment->delete;

# Expected: e5 (bumped to the front by its repeat), then e11..e6 and e4..e2 in
# descending recency. e1 and e0 fall past the 10-item limit; the screened and
# deleted entries are excluded.
my @want = map { $e[$_]->jitemid + 0 } ( 5, 11, 10, 9, 8, 7, 6, 4, 3, 2 );

# start from a clean active-entries cache, then read
LJ::MemCache::delete( [ $u->userid, "activeentries:" . $u->userid ] );
my @got = map { $_ + 0 } $u->active_entries;

is_deeply( \@got, \@want, "ten newest distinct commented entries, most-recent first" );

done_testing();
