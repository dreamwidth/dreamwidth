#!/usr/bin/perl
# t/plack-media.t
#
# Test media serving controllers (userpic, vgift, palimg) under Plack
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
use v5.10;

use Test::More;
use HTTP::Request::Common;
use Plack::Test;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";

    eval "use Plack::Test; 1" or do {
        plan skip_all => "Plack::Test required for integration tests";
    };
}

plan tests => 22;

# Load the Plack app
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Disable middleware concerns not under test (auth, sysban, rate limiting)
{
    no warnings 'redefine', 'once';

    *LJ::Session::session_from_cookies   = sub { return undef };
    *LJ::sysban_check                    = sub { return 0 };
    *LJ::Sysban::tempban_check           = sub { return 0 };
    *LJ::UniqCookie::parts_from_cookie   = sub { return () };
    *LJ::UniqCookie::ensure_cookie_value = sub { return };
    *LJ::User::Login::get_remote         = sub { return undef };
    *DW::RateLimit::get                  = sub { return undef };
}

# ---- Userpic tests ----

# Test 1: Userpic with If-Modified-Since returns 304
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "/userpic/12345/1";
    $req->header( 'If-Modified-Since' => 'Thu, 01 Jan 2026 00:00:00 GMT' );
    my $res = $cb->($req);

    is( $res->code, 304, "userpic returns 304 for If-Modified-Since" );
};

# Test 2: Userpic with invalid picid/userid returns 404 (no such user)
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/userpic/99999999/99999999" );

    is( $res->code, 404, "userpic returns 404 for nonexistent user/pic" );
};

# Test 3: Userpic with bad URL format returns 404
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/userpic/notanumber/1" );

    isnt( $res->code, 200, "userpic rejects non-numeric picid" );
};

# Test 4: /userpics (without /userpic/) should not match userpic route
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/userpics" );

    isnt( $res->code, 200, "/userpics does not match userpic route" );
};

# ---- VGift tests ----

# Test 5: VGift with If-Modified-Since returns 304
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "/vgift/12345/small";
    $req->header( 'If-Modified-Since' => 'Thu, 01 Jan 2026 00:00:00 GMT' );
    my $res = $cb->($req);

    is( $res->code, 304, "vgift returns 304 for If-Modified-Since" );
};

# Test 6: VGift IMS from admin interface should NOT return 304
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "/vgift/12345/small";
    $req->header( 'If-Modified-Since' => 'Thu, 01 Jan 2026 00:00:00 GMT' );
    $req->header( 'Referer'           => "$LJ::SITEROOT/admin/vgifts" );
    my $res = $cb->($req);

    isnt( $res->code, 304, "vgift does not return 304 when referer is admin" );
};

# Test 7: VGift with invalid size returns 404
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/vgift/12345/medium" );

    is( $res->code, 404, "vgift returns 404 for invalid size" );
};

# Test 8: VGift with valid size format but nonexistent pic returns 404
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/vgift/99999999/large" );

    is( $res->code, 404, "vgift returns 404 for nonexistent pic" );
};

# ---- PalImg tests ----

# Test 9: Basic palimg serves a real image
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/palimg/solid.png" );

    is( $res->code, 200, "palimg serves existing image" );
};

# Test 10: palimg has correct content type for PNG
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/palimg/solid.png" );

    is( $res->content_type, 'image/png', "palimg returns image/png for .png" );
};

# Test 11: palimg has correct content type for GIF
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/palimg/s1gradient.gif" );

    is( $res->content_type, 'image/gif', "palimg returns image/gif for .gif" );
};

# Test 12: palimg returns ETag header
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/palimg/solid.png" );

    ok( $res->header('ETag'), "palimg response includes ETag" );
};

# Test 13: palimg returns Last-Modified header
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/palimg/solid.png" );

    ok( $res->header('Last-Modified'), "palimg response includes Last-Modified" );
};

# Test 14: palimg with matching ETag returns 304
test_psgi $app, sub {
    my $cb = shift;

    # First request to get the ETag
    my $res1 = $cb->( GET "/palimg/solid.png" );
    my $etag = $res1->header('ETag');

    # Second request with If-None-Match
    my $req2 = GET "/palimg/solid.png";
    $req2->header( 'If-None-Match' => $etag );
    my $res2 = $cb->($req2);

    is( $res2->code, 304, "palimg returns 304 for matching ETag" );
};

# Test 15: palimg returns 404 for nonexistent file
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/palimg/nonexistent.gif" );

    is( $res->code, 404, "palimg returns 404 for nonexistent file" );
};

# Test 16: palimg rejects path traversal
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/palimg/../etc/passwd.gif" );

    is( $res->code, 404, "palimg rejects path traversal" );
};

# Test 17: palimg rejects unsupported extension
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/palimg/solid.jpg" );

    is( $res->code, 404, "palimg rejects non-gif/png extension" );
};

# Test 18: palimg with tint palette spec
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/palimg/solid.png/pte0d0ff" );

    is( $res->code, 200, "palimg with tint spec returns 200" );
};

# Test 19: palimg with gradient palette spec on GIF
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/palimg/s1gradient.gif/pg00ff000080ff8000" );

    is( $res->code, 200, "palimg with gradient spec returns 200" );
};

# Test 20: palimg with invalid palette spec returns 404
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/palimg/solid.png/pzzzinvalid" );

    is( $res->code, 404, "palimg with invalid palette spec returns 404" );
};

# Test 21: palimg with invalid extra path returns 404
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/palimg/solid.png/notpalette" );

    is( $res->code, 404, "palimg with non-palette extra returns 404" );
};

# Test 22: palimg HEAD request returns 200 with no body
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( HEAD "/palimg/solid.png" );

    is( $res->code, 200, "palimg HEAD returns 200" );
};
