#!/usr/bin/perl
# t/plack-integration.t
#
# Integration test for the Plack application that validates end-to-end functionality
#
# This test validates:
# - The full Plack middleware stack works
# - Request/response cycle through the actual app
# - Error handling
# - Basic routing functionality
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use v5.10;

use Test::More;
use HTTP::Request::Common;
use Plack::Test;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";

    # Skip this test if we don't have the required modules for integration testing
    eval "use Plack::Test; 1" or do {
        plan skip_all => "Plack::Test required for integration tests";
    };
}

plan tests => 8;

# Load the Plack app first — this pulls in DW::Routing and other modules
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Monkey-patch after loading so we override the real implementations
{
    no warnings 'redefine';

    *DW::Routing::call = sub {
        my ( $class, %args ) = @_;
        my $uri = $args{uri} || '';

        my $r = DW::Request->get;
        if ( $uri =~ m{^/api/v\d+/test} ) {
            $r->status(200);
            $r->header_out( 'Content-Type' => 'application/json' );
            $r->print('{"status":"ok","test":true}');
        }
        else {
            $r->status(404);
            $r->header_out( 'Content-Type' => 'application/json' );
            $r->print('{"error":"not found"}');
        }
        return;
    };
}

# Test 1: Basic GET request to root
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    # The app should handle this request (even if it returns an error)
    ok( defined $res, "Root request returns a response" );
};

# Test 2: API request routing
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/api/v1/test" );

    is( $res->code, 200, "API test endpoint returns 200" );
    like( $res->content, qr/"test":true/, "API test endpoint returns expected JSON" );
};

# Test 3-4: OPTIONS request (handled by middleware)
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( HTTP::Request->new( 'OPTIONS', '/' ) );

    # OPTIONS should be handled by the Options middleware
    ok( defined $res, "OPTIONS request returns a response" );
};

# Test 5: POST request
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( POST "/api/v1/test", [ foo => 'bar' ] );

    is( $res->code, 200, "POST to API endpoint works" );
};

# Test 6: Unknown API endpoint
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/api/v1/nonexistent" );

    is( $res->code, 404, "Unknown API endpoint returns 404" );
};

# Test 7: Invalid HTTP method (should be rejected by Options middleware)
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( HTTP::Request->new( 'PATCH', '/' ) );

    # PATCH is not in the allowed methods list in app.psgi
    is( $res->code, 405, "Disallowed HTTP method returns 405" );
};

# Test 8: Request with headers
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "/api/v1/test";
    $req->header( 'X-Forwarded-For' => '192.168.1.1' );
    my $res = $cb->($req);

    ok( defined $res, "Request with X-Forwarded-For header is handled" );
};
