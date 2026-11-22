# t/api-method-parameter.t
#
# Standalone tests for REST API method and parameter contracts.
#
# Authors:
#      Alex <saphid@users.noreply.github.com>
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
use Test::Exception;
use HTTP::Request;
use JSON ();

use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { $DW::Routing::DONT_LOAD = 1; }
use DW::API::Method;
use DW::API::Parameter;
use DW::Controller::API::REST;
use DW::Request;
use DW::Request::Standard;

my $json = JSON->new->convert_blessed->canonical;

subtest 'parameter validation and OpenAPI serialization' => sub {
    my %query = ( name => 'limit', in => 'query', description => 'Maximum results' );
    my $param = DW::API::Parameter->define_parameter(
        { %query, required => 1, schema => { type => 'integer', minimum => 1 } } );

    is(
        $json->encode($param),
        $json->encode(
            { %query, required => JSON::true, schema => { type => 'integer', minimum => 1 } }
        ),
        'a required query parameter has a JSON boolean and a numeric bound'
    );

    my $body = DW::API::Parameter->define_parameter(
        { %query, content => { 'application/json' => { schema => { type => 'integer' } } } } );
    is_deeply(
        $json->decode( $json->encode($body) ),
        { content => { 'application/json' => { schema => { type => 'integer' } } } },
        'a content-based parameter omits location metadata and private validators'
    );

    throws_ok { DW::API::Parameter->define_parameter( \%query ) }
    qr/content or schema/, 'rejects a parameter without a schema or content';
    throws_ok {
        DW::API::Parameter->define_parameter( { %query, schema => { type => 'invalid' } } );
    }
    qr/invalid schema/i, 'rejects an invalid parameter schema';
};

subtest 'method OpenAPI serialization' => sub {
    my $method = DW::API::Method->define_method(
        'post',
        sub { },
        {
            description => 'Create a resource',
            responses   => {
                201 => {
                    description => 'Created',
                    content     => { 'application/json' => { schema => { type => 'integer' } } },
                },
                400 => { description => 'Bad request' },
            },
        }
    );
    $method->param(
        {
            name        => 'limit',
            in          => 'query',
            description => 'Maximum results',
            schema      => { type => 'integer' }
        }
    );
    $method->body(
        { required => 1, content => { 'application/json' => { schema => { type => 'string' } } } }
    );

    is_deeply(
        $json->decode( $json->encode($method) ),
        {
            description => 'Create a resource',
            parameters  => [
                {
                    name        => 'limit',
                    in          => 'query',
                    description => 'Maximum results',
                    schema      => { type => 'integer' }
                }
            ],
            requestBody => {
                required => JSON::true,
                content  => { 'application/json' => { schema => { type => 'string' } } },
            },
            responses => {
                201 => {
                    description => 'Created',
                    content     => { 'application/json' => { schema => { type => 'integer' } } },
                },
                400 => { description => 'Bad request' },
            },
        },
        'publishes query, request body, and response definitions without validators'
    );
};

subtest 'HTTP responses honor the declared contract' => sub {
    my $method = DW::API::Method->define_method(
        'get',
        sub { },
        {
            responses => {
                200 => {
                    description => 'Success',
                    content     => { 'application/json' => { schema => { type => 'object' } } },
                },
                404 => { description => 'Resource not found' },
            },
        }
    );

    my $request = new_request();
    throws_ok { $method->rest_ok( [] ) }
    qr/invalid response format/i, 'rejects a response that violates its schema';
    is( $request->response_content, '', 'does not write an invalid response' );

    $request->status(202);
    $method->rest_ok( { title => 'Example' } );
    is( $request->status, 200, 'defaults a response with a body to 200' );
    is( $request->header_out('Content-Type'), 'application/json', 'defaults to JSON' );
    is_deeply(
        $json->decode( $request->response_content ),
        { title => 'Example' },
        'writes the JSON response body'
    );

    $request = new_request();
    $method->rest_ok(undef);
    is( $request->status,           204, 'defaults a response without a body to 204' );
    is( $request->response_content, '',  'writes no body for a 204 response' );

    $request = new_request();
    $method->rest_error(404);
    is( $request->status, 404, 'preserves the error status' );
    is( $request->header_out('Content-Type'), 'application/json', 'returns errors as JSON' );
    my $error = $json->decode( $request->response_content );
    is( $error->{success}, 0, 'marks the response as a failure' );
    like( $error->{error}, qr/not found/i, 'defaults to the configured response description' );
    DW::Request->reset;
};

ok( !grep( m{(?:^|/)ljlib\.pl\z}, keys %INC ), 'runs without loading ljlib.pl' );

done_testing;

sub new_request {
    DW::Request->reset;
    return DW::Request::Standard->new( HTTP::Request->new( 'GET', '/example' ) );
}
