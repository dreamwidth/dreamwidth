#!/usr/bin/perl
#
# t/plack-access-filters.t
#
# Access-filter HTTP contracts, persistence and entry visibility.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use Plack::Test;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'accessFiltersTest';
my $owner    = temp_user();
my $friend   = temp_user();
my $stranger = temp_user();
my $comm     = temp_comm();
LJ::set_rel( $comm, $owner, 'A' );
$owner->add_edge( $friend, trust => { mask => 1, nonotify => 1 } );
my $url = 'http://localhost/manage/circle/editfilters?as=' . $owner->user;

{
    test_psgi $app, sub {
        my $cb  = shift;
        my $res = $cb->( GET $url );
        is( $res->code, 200, 'editor loads' );
        like( $res->content, qr/Manage Access Filters/, 'title translated' );
        my ($token) = $res->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        ok( $token, 'signed form token' );
        my $save = sub {
            return $cb->( POST $url, Content => [ mode => 'save', lj_form_auth => $token, @_ ] );
        };

        $res = $save->(
            efg_set_1_name                       => 'First',
            efg_set_1_sort                       => 5,
            efg_set_31_name                      => 'Middle',
            efg_set_31_sort                      => 10,
            efg_set_60_name                      => 'Last',
            efg_set_60_sort                      => 15,
            'editfriend_maskhi_' . $friend->user => ( 1 | ( 1 << 29 ) ),
            'editfriend_masklo_' . $friend->user => 3
        );
        is( $res->code, 200, 'save response' );
        like( $res->content, qr/Your access filters are now saved/, 'save message' );
        is( $owner->trust_groups( id => 60 )->{groupname}, 'Last', 'group 60 persisted' );
        is( $owner->trustmask($friend), 3 | ( 1 << 31 ) | ( 1 << 60 ), 'both mask halves survive' );

        $res = $save->(
            efg_set_1_name   => 'Renamed',
            efg_set_1_sort   => 20,
            efg_set_1_public => 1
        );
        my $group = $owner->trust_groups( id => 1 );
        is( $group->{groupname}, 'Renamed', 'rename persisted' );
        is( $group->{sortorder}, 20,        'order persisted' );
        is( $group->{is_public}, 1,         'public flag preserved' );

        $res = $save->(
            efg_set_1_name  => 'Should not save',
            efg_set_1_sort  => 5,
            efg_set_60_name => 'Invalid, name',
            efg_set_60_sort => 10
        );
        like( $res->content, qr/names containing commas/, 'comma validation renders' );
        is( $owner->trust_groups( id => 1 )->{groupname},
            'Renamed', 'all names validated before mutation' );

        $res = $cb->(
            POST $url, Content => [ mode => 'save', lj_form_auth => 'invalid', efg_delete_1 => 1 ]
        );
        ok( $owner->trust_groups( id => 1 ), 'invalid token does not delete' );
        unlike(
            $res->content,
            qr/Your access filters are now saved/,
            'invalid token does not claim success'
        );

        $res = $cb->(
            POST "$url&authas=" . $stranger->user,
            Content => [
                mode           => 'save',
                lj_form_auth   => $token,
                efg_set_1_name => 'Forbidden',
                efg_set_1_sort => 5
            ]
        );
        ok( !$stranger->trust_groups( id => 1 ), 'unauthorized authas cannot mutate' );
        $res = $cb->( GET "$url&authas=" . $comm->user );
        like(
            $res->content,
            qr/Communities cannot currently use access filters/,
            'community unavailable message'
        );

        $res = $cb->(
            POST "$url&authas=" . $comm->user,
            Content => [
                mode           => 'save',
                lj_form_auth   => $token,
                efg_set_1_name => 'Forbidden community group',
                efg_set_1_sort => 5
            ]
        );
        ok( !$comm->trust_groups( id => 1 ), 'forged community save cannot create filters' );

        $res = $save->(
            'editfriend_groupmask_' . $friend->user   => 3,
            'editfriend_groupmask_' . $stranger->user => 3
        );
        is( $owner->trustmask($friend), 3, 'legacy whole mask accepted' );
        ok( !$owner->trusts($stranger), 'submission does not add an untrusted user' );

        my $entry = $owner->t_post_fake_entry( security => 'friends' );
        $owner->do( 'UPDATE log2 SET allowmask = 2 WHERE journalid = ? AND jitemid = ?',
            undef, $owner->id, $entry->jitemid );
        $owner->do( 'UPDATE logsec2 SET allowmask = 2 WHERE journalid = ? AND jitemid = ?',
            undef, $owner->id, $entry->jitemid );
        LJ::MemCache::delete( [ $owner->id, 'log2:' . $owner->id . ':' . $entry->jitemid ] );
        $entry = LJ::Entry->new( $owner, jitemid => $entry->jitemid );
        ok( $entry->visible_to($friend), 'member can read group-secured entry' );
        $res = $save->( efg_delete_1 => 1, 'editfriend_groupmask_' . $friend->user => 3 );
        ok( !$owner->trust_groups( id => 1 ), 'group deleted' );
        is( $owner->trustmask($friend), 1, 'deleted membership cleared, trust preserved' );
        $entry = LJ::Entry->new( $owner, jitemid => $entry->jitemid );
        ok( !$entry->visible_to($friend), 'deleted group no longer grants entry access' );

        $owner->remove_edge( $friend, trust => { nonotify => 1 } );
        $res = $save->( 'editfriend_groupmask_' . $friend->user => 3 );
        ok( !$owner->trusts($friend), 'stale save cannot restore a removed trust edge' );

        for my $path ( '/manage/circle/editfilters', '/manage/circle/editfilters.bml' ) {
            $res = $cb->( GET "http://localhost$path?as=" . $owner->user );
            is( $res->code, 200, "$path remains accessible" );
        }
        $res = $cb->( GET 'http://localhost/manage/circle/editfilters?as=no_such_fixture' );
        unlike( $res->content, qr/name=['"]efg_set_1_name/, 'anonymous user gets no editor' );
    };
};
done_testing;
