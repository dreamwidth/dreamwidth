# t/plack-api-journals.t
#
# REST API journal endpoints: access lists, tags, and crosspost accounts.
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
use lib "$ENV{LJHOME}/t/lib";
use LJ::Test;
use DW::Test::API;

my ( $owner,    $okey ) = api_user();
my ( $stranger, $skey ) = api_user();
my $ou   = $owner->user;
my $base = "/journals/$ou";

subtest 'owner-only endpoints' => sub {
    my $group    = $owner->create_trust_group( groupname => 'private group' );
    my @requests = (
        [ GET    => "$base/accesslists" ],
        [ POST   => "$base/accesslists", json => { name => 'x' } ],
        [ DELETE => "$base/accesslists", query => { id => $group } ],
        [ GET    => "$base/accesslists/$group" ],
        [ POST   => "$base/accesslists/$group", json  => [ $stranger->user ] ],
        [ POST   => "$base/tags",               json  => ['x'] ],
        [ DELETE => "$base/tags",               query => { tag => 'x' } ],
        [ GET    => "$base/xpostaccounts" ],
    );
    for my $req (@requests) {
        my ( $method, $path, %opts ) = @$req;
        my ( $res, $body ) = api_request( $method, $path, key => $skey, %opts );
        is( $res->code, 403, "$method $path is owner-only" );
    }
    ok( $owner->trust_groups( id => $group ), 'group untouched' );
};

subtest 'access lists' => sub {
    my ( $member, $mkey ) = api_user();
    $owner->add_edge( $member, trust => { nonotify => 1 } );

    my ( $res, $body ) =
        api_request( POST => "$base/accesslists", key => $okey, json => { name => 'friends' } );
    is( $res->code, 200, 'create access list' );
    my $id = $body->{id};
    ok( $id, 'create returns the id' );

    ( $res, $body ) = api_request( GET => "$base/accesslists", key => $okey );
    ok( ( grep { $_->{id} == $id && $_->{name} eq 'friends' } @$body ), 'list includes it' );

    ( $res, $body ) = api_request(
        POST => "$base/accesslists/$id",
        key  => $okey,
        json => [ $member->user ]
    );
    is( $res->code, 200, 'add a member' );

    ( $res, $body ) = api_request( GET => "$base/accesslists/$id", key => $okey );
    is_deeply( $body, [ $member->user ], 'member is listed' );

    for my $bad ( 0, 61, 99 ) {
        ( $res, $body ) = api_request( GET => "$base/accesslists/$bad", key => $okey );
        is( $res->code, 400, "access list id $bad is rejected" );
    }

    ( $res, $body ) =
        api_request( DELETE => "$base/accesslists", key => $okey, query => { id => $id } );
    is( $res->code, 204, 'delete access list' );
    ok( !$owner->trust_groups( id => $id ), 'access list is gone' );

    ( $res, $body ) =
        api_request( DELETE => "$base/accesslists", key => $okey, query => { id => $id } );
    is( $res->code, 404, 'deleting it again is a 404' );
};

subtest 'tags' => sub {
    my ( $res, $body ) =
        api_request( POST => "$base/tags", key => $okey, json => [ 'alpha', 'beta' ] );
    is( $res->code, 204, 'create tags' );

    ( $res, $body ) = api_request( GET => "$base/tags", key => $okey );
    is( $res->code, 200, 'list tags' );
    is_deeply( [ map { $_->{name} } @$body ], [ 'alpha', 'beta' ], 'tags listed by name' );
    is( $body->[0]{use_count}, 0, 'unused tag has a zero use count' );

    ( $res, $body ) =
        api_request( DELETE => "$base/tags", key => $okey, query => { tag => 'alpha' } );
    is( $res->code, 204, 'delete a tag' );

    ( $res, $body ) = api_request( GET => "$base/tags", key => $okey );
    is_deeply( [ map { $_->{name} } @$body ], ['beta'], 'deleted tag is gone' );

    ( $res, $body ) = api_request( POST => "$base/tags", key => $okey, json => ['<b>'] );
    is( $res->code, 400, 'one invalid tag is rejected' );

    ( $res, $body ) =
        api_request( POST => "$base/tags", key => $okey, json => [ '<b>', '<i>' ] );
    is( $res->code, 400, 'several invalid tags are rejected' );
    like( $body->{error}, qr/[a-z]/i, 'with an error message' );
};

subtest 'tag visibility' => sub {
    my ( $writer, $wkey ) = api_user();
    my $wbase = '/journals/' . $writer->user;
    api_request(
        POST => "$wbase/entries",
        key  => $wkey,
        json => { text => 'secret', security => 'private', tags => ['hidden'] }
    );
    api_request(
        POST => "$wbase/entries",
        key  => $wkey,
        json => { text => 'open', tags => ['shown'] }
    );

    my ( $res, $body ) = api_request( GET => "$wbase/tags", key => $wkey );
    is_deeply( [ map { $_->{name} } @$body ], [ 'hidden', 'shown' ], 'owner sees every tag' );

    ( $res, $body ) = api_request( GET => "$wbase/tags", key => $skey );
    is_deeply( [ map { $_->{name} } @$body ], ['shown'], 'stranger sees only public tags' );
};

subtest 'crosspost accounts' => sub {
    my ( $res, $body ) = api_request( GET => "$base/xpostaccounts", key => $okey );
    is( $res->code, 200, 'list crosspost accounts' );
    is_deeply( $body, [], 'none configured' );
};

# Rate limit state lives in memcache, which tests don't otherwise have.
LJ::Test::with_fake_memcache {
    subtest 'rate limiting' => sub {
        my ( $busy, $bkey ) = api_user();
        my $path = '/journals/' . $busy->user . '/accesslists';

        # Access list creation allows 10 requests per minute.
        my @codes = map {
            my ( $res, $body ) =
                api_request( POST => $path, key => $bkey, json => { name => "g$_" } );
            $res->code
        } 1 .. 10;
        is_deeply( \@codes, [ (200) x 10 ], 'requests within the limit succeed' );

        my ( $res, $body ) = api_request( POST => $path, key => $bkey, json => { name => 'g11' } );
        is( $res->code, 429, 'request over the limit is refused' );
        ok( $res->header('Retry-After'), 'with a Retry-After header' );
        ok( $body->{retry_after},        'and retry_after in the body' );
    };
};

done_testing;
