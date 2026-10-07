# t/plack-api-framework.t
#
# REST API framework: key authentication, routing, request validation, error
# responses, and the spec endpoint.
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
use DW::API::Key;
use DW::Test::API;

my ( $u, $key ) = api_user();
my $user = $u->user;
my $path = "/journals/$user/tags";

subtest 'spec' => sub {
    my ( $res, $spec ) = api_request( GET => '/spec' );
    is( $res->code,       200,     'spec is available without a key' );
    is( $spec->{openapi}, '3.0.0', 'spec declares OpenAPI 3' );
    is_deeply(
        [ sort keys %{ $spec->{paths} } ],
        [
            sort qw(
                /spec /comments/screening /comments/settings
                /users/{username}/icons /users/{username}/icons/{picid}
                /journals/{username}/entries /journals/{username}/entries/{entry_id}
                /journals/{username}/accesslists /journals/{username}/accesslists/{accesslistid}
                /journals/{username}/tags /journals/{username}/xpostaccounts
                )
        ],
        'spec lists every registered path'
    );
};

subtest 'key authentication' => sub {
    my ( $res, $body ) = api_request( GET => $path );
    is( $res->code, 401, 'no Authorization header' );
    is_deeply(
        $body,
        { success => 0, error => 'Missing or invalid API key' },
        'standard error body'
    );

    ( $res, $body ) = api_request( GET => $path, key => 'notarealkey' );
    is( $res->code, 401, 'unknown key' );

    ( $res, $body ) = api_request( GET => $path, key => $key );
    is( $res->code, 200, 'valid key' );

    ( $res, $body ) = api_request( GET => $path, auth => "Basic $key" );
    is( $res->code, 401, 'other auth schemes are rejected' );

TODO: {
        local $TODO = 'Bearer scheme parsing is loose';

        ( $res, $body ) = api_request( GET => $path, auth => "bearer $key" );
        is( $res->code, 200, 'auth scheme is case-insensitive' );

        ( $res, $body ) = api_request( GET => $path, auth => "BEARER  $key" );
        is( $res->code, 200, 'auth scheme in capitals with extra whitespace' );

        ( $res, $body ) = api_request( GET => $path, auth => $key );
        is( $res->code, 401, 'key without the Bearer scheme is rejected' );
    }

    my $old = DW::API::Key->new_for_user($u);
    ( $res, $body ) = api_request( GET => $path, key => $old->hash );
    is( $res->code, 200, 'second key works' );
    $old->delete($u);
    ( $res, $body ) = api_request( GET => $path, key => $old->hash );
    is( $res->code, 401, 'deleted key stops working immediately' );
};

subtest 'API key validation' => sub {
    for my $statusvis (qw( S D X )) {
        my ( $su, $skey ) = api_user();
        my $spath = '/journals/' . $su->user . '/tags';

        # The first request caches the key lookup.
        my ( $res, $body ) = api_request( GET => $spath, key => $skey );
        is( $res->code, 200, "key works before the change to $statusvis" );

        $su->update_self( { statusvis => $statusvis } );

    TODO: {
            local $TODO = 'API key validation is incomplete';

            ( $res, $body ) = api_request( GET => $spath, key => $skey );
            is( $res->code, 401, "key stops working when the account is not active ($statusvis)" );
        }
    }
};

subtest 'request bodies' => sub {
    my ( $res, $body );
TODO: {
        local $TODO = 'unsupported or missing bodies die in body validation';

        ( $res, $body ) =
            api_request( POST => $path, key => $key, json => 'x', content_type => 'text/plain' );
        is( $res->code, 415, 'text/plain body is rejected as unsupported' );

        ( $res, $body ) =
            api_request( POST => $path, key => $key, json => '["a"]', content_type => '' );
        is( $res->code, 415, 'body with no content type is rejected as unsupported' );

        ( $res, $body ) = api_request( POST => $path, key => $key );
        is( $res->code, 400, 'missing required body is a 400' );
    }

    ( $res, $body ) = api_request( POST => $path, key => $key, json => '{"broken' );
    is( $res->code, 400, 'malformed JSON is a 400' );
TODO: {
        local $TODO = 'body errors have an empty message';

        like( $body->{error}, qr/JSON/, 'malformed JSON error says why' );
    }

    ( $res, $body ) = api_request(
        POST => "/journals/$user/entries",
        key  => $key,
        json => { text => 'x', tags => 'not-an-array' }
    );
    is( $res->code, 400, 'schema violation is a 400' );
TODO: {
        local $TODO = 'body errors have an empty message';

        like( $body->{error}, qr/tags/, 'schema violation error names the field' );
    }
};

subtest 'routing and parameters' => sub {
    my ( $res, $body ) = api_request( DELETE => "/journals/$user/entries/1", key => $key );
    is( $res->code,       405, 'method missing from the spec is a 405' );
    is( $body->{success}, 0,   '405 has a JSON error body' );

    ( $res, $body ) = api_request( GET => '/no/such/route', key => $key );
    is( $res->code, 404, 'unknown route is a 404' );

    ( $res, $body ) = api_request( GET => '/journals/nosuchuser0000/tags', key => $key );
    is( $res->code, 404, 'unknown journal is a 404' );

    ( $res, $body ) = api_request( GET => '/journals/' . ( 'a' x 30 ) . '/tags', key => $key );
    is( $res->code, 400, 'over-long username fails parameter validation' );
    like( $body->{error}, qr/username/, 'parameter error names the parameter' );

TODO: {
        local $TODO = 'route regexes are not anchored at the start';

        ( $res, $body ) = api_request( GET => '/extra/prefix/spec' );
        is( $res->code, 404, 'route does not match with a prefix' );
    }
};

subtest 'static comment endpoints' => sub {
    for my $endpoint (qw( screening settings )) {
        my ( $res, $body ) = api_request( GET => "/comments/$endpoint" );
        is( $res->code, 401, "$endpoint needs a key" );

        ( $res, $body ) = api_request( GET => "/comments/$endpoint", key => $key );
        is( $res->code, 200, "$endpoint with a key" );
        ok( exists $body->{''}, "$endpoint includes the default option" );
    }
};

done_testing;
