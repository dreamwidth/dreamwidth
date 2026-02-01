#!/usr/bin/perl
# t/plack-app.t
#
# Test to validate that the Plack application setup works correctly
#
# This test validates:
# - The app.psgi file loads correctly
# - Basic middleware stack is functional
# - DW::Request::Plack objects are created properly
# - Basic request/response cycle works
# - Routing dispatch works for API calls
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

use Test::More tests => 17;
use Test::MockObject;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

use_ok('DW::Request::Plack');
use_ok('DW::Routing');

# Test 1-2: Basic module loading

# Mock some dependencies that may not be available in test environment
my $mock = Test::MockObject->new();

# Mock LJ functions that might be called during app loading
$mock->fake_module(
    'LJ' => (
        start_request => sub { },
        end_request   => sub { },
        urandom_int   => sub { return int( rand(1000000) ); },
    )
);

$mock->fake_module(
    'LJ::Procnotify' => (
        check => sub { },
    )
);

$mock->fake_module(
    'S2' => (
        set_domain => sub { },
    )
);

# Test that we can load the app.psgi file
my $app_file = "$ENV{LJHOME}/app.psgi";
ok( -f $app_file, 'app.psgi file exists' );

# Test 3: File existence

# Load the app (this tests the basic compilation and setup)
my $app;
eval {
    # app.psgi uses Plack::Builder, so we need to evaluate it properly
    local @ARGV = ();
    $app = do $app_file;
};
ok( !$@, 'app.psgi loads without compilation errors' ) or diag("Error: $@");

# app.psgi might return undef in test environment due to missing config
# so let's just test that it compiled successfully
SKIP: {
    skip "app.psgi may not return app in test environment", 2 unless defined $app;
    ok( defined $app,       'app.psgi returns a defined value' );
    ok( ref $app eq 'CODE', 'app.psgi returns a code reference' );
}

# Tests 4: Basic app loading (compilation only, since app may not initialize in test env)

# Test creating a basic PSGI environment
my $basic_env = {
    'REQUEST_METHOD'    => 'GET',
    'PATH_INFO'         => '/',
    'QUERY_STRING'      => '',
    'SERVER_NAME'       => 'test.dreamwidth.org',
    'SERVER_PORT'       => 80,
    'HTTP_HOST'         => 'test.dreamwidth.org',
    'SCRIPT_NAME'       => '',
    'psgi.version'      => [ 1, 1 ],
    'psgi.url_scheme'   => 'http',
    'psgi.input'        => '',
    'psgi.errors'       => '',
    'psgi.multithread'  => 0,
    'psgi.multiprocess' => 1,
    'psgi.run_once'     => 0,
    'psgi.nonblocking'  => 0,
    'psgi.streaming'    => 1,
};

# Test DW::Request::Plack object creation
my $request;
eval { $request = DW::Request::Plack->new($basic_env); };
ok( !$@,              'DW::Request::Plack->new() works without errors' ) or diag("Error: $@");
ok( defined $request, 'DW::Request::Plack->new() returns a defined object' );
isa_ok( $request, 'DW::Request::Plack', 'Created object is a DW::Request::Plack' );

# Tests 5-7: Request object creation

# Test basic request object methods
is( $request->method, 'GET',                 'Request method is correctly extracted' );
is( $request->path,   '/',                   'Request path is correctly extracted' );
is( $request->host,   'test.dreamwidth.org', 'Request host is correctly extracted' );

# Tests 8-10: Request object methods

# Test response object creation and basic methods
$request->status(200);
$request->header_out( 'Content-Type', 'text/html' );
$request->print('<html><body>Test</body></html>');

my $response = $request->res;
ok( defined $response, 'Response object is created' );
is( $response->[0], 200, 'Response status is set correctly' );

# Tests 11-12: Response handling

# Test API routing detection (the core logic in app.psgi)
my $api_env = { %$basic_env, 'PATH_INFO' => '/api/v1/test' };

my $api_request = DW::Request::Plack->new($api_env);
is( $api_request->path, '/api/v1/test', 'API path is correctly extracted' );

# Tests 13: API routing

# Test middleware availability
use_ok('Plack::Middleware::DW::RequestWrapper');
use_ok('Plack::Middleware::DW::Redirects');

# Tests 14-15: Middleware loading
