#!/usr/bin/perl
# t/plack-static.t
#
# Tests for static file serving via Plack middleware:
# - Plain static files (Plack::Middleware::Static)
# - Concatenated resources (Plack::Middleware::DW::ConcatRes)
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

    eval "use Plack::Test; 1" or do {
        plan skip_all => "Plack::Test required for static tests";
    };
}

plan tests => 10;

# Load the Plack app
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Test 1: Plain static CSS file returns 200
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/stc/lj_base.css" );

    is( $res->code, 200, "Plain static CSS file returns 200" );
};

# Test 2: Static CSS has correct content type
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/stc/lj_base.css" );

    like( $res->header('Content-Type'), qr{text/css}, "Static CSS has text/css content type" );
};

# Test 3: Static file has content
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/stc/lj_base.css" );

    ok( length( $res->content ) > 0, "Static CSS file has content" );
};

# Test 4: Non-existent static file returns 404
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/stc/nonexistent_file_abc123.css" );

    is( $res->code, 404, "Non-existent static file returns 404" );
};

# Test 5: Concatenated CSS request returns 200
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/stc/css/skins/??celerity.css,lynx.css" );

    is( $res->code, 200, "Concatenated CSS request returns 200" );
};

# Test 6: Concatenated response contains content from both files
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/stc/css/skins/??celerity.css,lynx.css" );

    my $body = $res->content;
    ok( length($body) > 0, "Concatenated response has content" );
};

# Test 7: Concat with cache buster works
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/stc/css/skins/??celerity.css,lynx.css?v=1234567890" );

    is( $res->code, 200, "Concat with cache buster returns 200" );
};

# Test 8: Path traversal returns 404
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/stc/css/??../../etc/passwd" );

    is( $res->code, 404, "Path traversal attempt returns 404" );
};

# Test 9: Mixed file types returns 404
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/stc/??lj_base.css,fake.js" );

    is( $res->code, 404, "Mixed CSS and JS in concat returns 404" );
};

# Test 10: Missing file in concat returns 404
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/stc/css/skins/??nonexistent_abc123.css" );

    is( $res->code, 404, "Missing file in concat returns 404" );
};
