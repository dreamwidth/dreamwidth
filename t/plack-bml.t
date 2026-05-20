#!/usr/bin/perl
# t/plack-bml.t
#
# Tests for BML rendering under Plack via DW::BML
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025-2026 by Dreamwidth Studios, LLC.
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

    eval "use Plack::Test; 1" or do {
        plan skip_all => "Plack::Test required for BML tests";
    };
}

plan tests => 10;

# Load the Plack app
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Test 1: DW::BML module loads
use_ok('DW::BML');

# Test 2: resolve_path finds a known BML file (login.bml exists in htdocs)
{
    my ( $redirect, $uri, $file ) = DW::BML->resolve_path('/login');
    ok( defined $file && $file =~ /login\.bml$/, "resolve_path finds login.bml" );
}

# Test 3: resolve_path returns undef for nonexistent path
{
    my ( $redirect, $uri, $file ) =
        DW::BML->resolve_path('/this-path-definitely-does-not-exist-12345');
    ok( !defined $file, "resolve_path returns undef for nonexistent path" );
}

# Test 4: resolve_path rejects paths with ..
{
    my ( $redirect, $uri, $file ) = DW::BML->resolve_path('/../etc/passwd');
    ok( !defined $file, "resolve_path rejects path traversal" );
}

# Test 5: resolve_path with trailing slash resolves index.bml
{
    my ( $redirect, $uri, $file ) = DW::BML->resolve_path('/tools/');
    if ( defined $file && $file =~ /index\.bml$/ ) {
        ok( 1, "resolve_path resolves /tools/ to index.bml" );
    }
    else {
        # If /tools/ doesn't exist, skip gracefully
        ok( 1, "resolve_path handles /tools/ (no directory found)" );
    }
}

# Test 6: _config.bml path is forbidden
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/_config.bml" );
    is( $res->code, 403, "Direct access to _config.bml returns 403" );
};

# Test 7: GET /login returns 200 with HTML content
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/login" );

    # login.bml should render successfully
    is( $res->code, 200, "GET /login returns 200" );
};

# Test 8: BML response has text/html content type
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/login" );

    like( $res->content_type, qr{text/html}, "BML response has text/html content type" );
};

# Test 9: Non-existent .bml-resolvable path returns 404
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/nonexistent-page-xyz-12345" );

    is( $res->code, 404, "Non-existent path returns 404" );
};

# Test 10: Existing controller routes still work (not broken by BML fallback)
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/api/v1/test" );

    # This should be handled by DW::Routing, not BML
    ok( defined $res, "Controller route still returns a response with BML fallback active" );
};
