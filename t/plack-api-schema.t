# t/plack-api-schema.t
#
# REST API schema validation and request parameter coercion.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
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
use JSON;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test ();
use DW::Controller::API::REST;

subtest 'schema definitions are validated' => sub {
    for my $case (
        [ 'unknown type', { type => 'not-a-json-type' } ],
        [ 'invalid required', { type => 'object', required => 'name' } ],
        [
            'invalid nested schema',
            { type => 'object', properties => { name => { type => 'string', minLength => -1 } } }
        ],
        )
    {
        my ( $name, $schema ) = @$case;
        my $target = { schema => $schema };
        eval { DW::Controller::API::REST::schema($target) };
        like( $@, qr/Invalid schema!/, $name );
        ok( !exists $target->{validator}, 'invalid schema has no data validator' );
    }

    eval { DW::Controller::API::REST::schema( {} ) };
    like( $@, qr/No schema defined!/, 'missing schema is rejected' );
};

subtest 'data validation retains schema constraints' => sub {
    my $target = {
        schema => {
            type       => 'object',
            properties => {
                count => { type => 'integer', minimum => 1 },
                name  => { type => 'string' },
            },
            required             => ['count'],
            additionalProperties => JSON::false,
        },
    };
    DW::Controller::API::REST::schema($target);
    my $validator = $target->{validator};
    ok( $validator, 'data validator is attached' );
    is_deeply( [ $validator->validate( { count => 2, name => 'example' } ) ], [], 'valid data' );

    for my $case (
        [ 'missing required field', {} ],
        [ 'wrong value type',       { count => [] } ],
        [ 'below minimum',          { count => 0 } ],
        [ 'unexpected property',    { count => 2, extra => 'x' } ],
        )
    {
        my ( $name, $data ) = @$case;
        ok( scalar( $validator->validate($data) ), $name );
    }
};

subtest 'request parameters retain scalar coercion' => sub {
    for my $case (
        [ 'integer', '42',   '[42]' ],
        [ 'boolean', 'true', '[true]' ],
        [ 'string',  42,     '["42"]' ],
        )
    {
        my ( $type, $value, $expected ) = @$case;
        my $target = bless { schema => { type => $type } }, 'DW::API::Parameter';
        DW::Controller::API::REST::schema($target);
        is_deeply( [ $target->{validator}->validate($value) ], [], "$type parameter is accepted" );
        is( to_json( [$value] ), $expected, "$type parameter has the coerced JSON type" );
    }

    my $response = { schema => { type => 'boolean' } };
    DW::Controller::API::REST::schema($response);
    my $value = 'true';
    ok( scalar( $response->{validator}->validate($value) ), 'response boolean stays strict' );
    is( to_json( [$value] ), '["true"]', 'response is not coerced' );
};

done_testing;
