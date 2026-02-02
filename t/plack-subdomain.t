#!/usr/bin/perl
# t/plack-subdomain.t
#
# Test subdomain function middleware (shop, support, mobile redirects/rewrites)
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

plan tests => 18;

# Load the Plack app
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Stub routing so we can observe what URI reaches the app
my $routed_uri;
{
    no warnings 'redefine';
    *DW::Routing::call = sub {
        my ( $class, %args ) = @_;
        $routed_uri = $args{uri} || '';
        my $r = DW::Request->get;
        $r->status(200);
        $r->header_out( 'Content-Type' => 'text/plain' );
        $r->print("routed:$routed_uri");
        return;
    };
}

# Configure subdomain functions for testing
local $LJ::USER_DOMAIN   = 'example.org';
local $LJ::DOMAIN_WEB    = 'www.example.org';
local $LJ::DOMAIN        = 'example.org';
local $LJ::SITEROOT      = 'https://www.example.org';
local $LJ::PROTOCOL      = 'https';
local %LJ::SUBDOMAIN_FUNCTION = (
    shop    => 'shop',
    support => 'support',
    mobile  => 'mobile',
);

# --- shop.example.org with SUBDOMAIN_FUNCTION{shop} = 'shop' ---
# Should redirect to $SITEROOT/shop$uri

# Test 1: shop subdomain redirects to /shop/randomgift
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://shop.example.org/randomgift";
    my $res = $cb->($req);

    is( $res->code, 303, "shop subdomain returns redirect" );
};

# Test 2: shop redirect Location is correct
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://shop.example.org/randomgift";
    my $res = $cb->($req);

    is(
        $res->header('Location'),
        'https://www.example.org/shop/randomgift',
        "shop subdomain redirects to SITEROOT/shop/path"
    );
};

# Test 3: shop subdomain root redirects to /shop
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://shop.example.org/";
    my $res = $cb->($req);

    is(
        $res->header('Location'),
        'https://www.example.org/shop',
        "shop subdomain root redirects to SITEROOT/shop (trailing slash stripped)"
    );
};

# Test 4: shop subdomain preserves query string
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://shop.example.org/randomgift?type=paid";
    my $res = $cb->($req);

    is(
        $res->header('Location'),
        'https://www.example.org/shop/randomgift?type=paid',
        "shop subdomain redirect preserves query string"
    );
};

# --- support.example.org ---

# Test 5: support subdomain redirects
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://support.example.org/submit";
    my $res = $cb->($req);

    is( $res->code, 303, "support subdomain returns redirect" );
};

# Test 6: support redirect goes to /support/
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://support.example.org/submit";
    my $res = $cb->($req);

    is(
        $res->header('Location'),
        'https://www.example.org/support/',
        "support subdomain redirects to SITEROOT/support/"
    );
};

# --- mobile.example.org ---

# Test 7: mobile subdomain redirects
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://mobile.example.org/read";
    my $res = $cb->($req);

    is( $res->code, 303, "mobile subdomain returns redirect" );
};

# Test 8: mobile redirect preserves path
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://mobile.example.org/read";
    my $res = $cb->($req);

    is(
        $res->header('Location'),
        'https://www.example.org/mobile/read',
        "mobile subdomain redirects to SITEROOT/mobile/path"
    );
};

# --- www.example.org (no subdomain function) ---

# Test 9: www domain passes through without redirect
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://www.example.org/shop/randomgift";
    my $res = $cb->($req);

    is( $res->code, 200, "www domain request passes through (no redirect)" );
};

# Test 10: www domain routes to correct URI
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://www.example.org/shop/randomgift";
    $cb->($req);

    is( $routed_uri, '/shop/randomgift', "www domain routes to /shop/randomgift" );
};

# --- www.shop.example.org (www prefix on subdomain) ---

# Test 11: www.shop.example.org redirects to drop www prefix
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://www.shop.example.org/randomgift";
    my $res = $cb->($req);

    is( $res->code, 303, "www.subdomain redirects" );
};

# Test 12: www.shop redirect drops www prefix
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://www.shop.example.org/randomgift";
    my $res = $cb->($req);

    is(
        $res->header('Location'),
        'https://shop.example.org/randomgift',
        "www.shop.example.org redirects to shop.example.org"
    );
};

# --- shop subdomain with no SUBDOMAIN_FUNCTION entry (rewrite, not redirect) ---

# Test 13-14: Without SUBDOMAIN_FUNCTION, shop subdomain rewrites URI inline
{
    local %LJ::SUBDOMAIN_FUNCTION = ();    # clear all functions

    test_psgi $app, sub {
        my $cb  = shift;
        my $req = GET "http://shop.example.org/randomgift";
        my $res = $cb->($req);

        is( $res->code, 200, "shop subdomain without func passes through (rewrite)" );
    };

    test_psgi $app, sub {
        my $cb  = shift;
        my $req = GET "http://shop.example.org/randomgift";
        $cb->($req);

        is( $routed_uri, '/shop/randomgift',
            "shop subdomain without func rewrites /randomgift to /shop/randomgift" );
    };
}

# --- shop rewrite strips trailing slash ---

# Test 15-16: Rewrite mode strips trailing slash before prepending /shop
{
    local %LJ::SUBDOMAIN_FUNCTION = ();

    test_psgi $app, sub {
        my $cb  = shift;
        my $req = GET "http://shop.example.org/";
        $cb->($req);

        is( $routed_uri, '/shop', "shop rewrite strips trailing slash from root" );
    };

    test_psgi $app, sub {
        my $cb  = shift;
        my $req = GET "http://shop.example.org/cart/";
        $cb->($req);

        is( $routed_uri, '/shop/cart', "shop rewrite strips trailing slash from path" );
    };
}

# --- Non-functional subdomain passes through ---

# Test 17-18: Unknown subdomain is not handled by SubdomainFunction
test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://someuser.example.org/profile";
    my $res = $cb->($req);

    ok( defined $res, "unknown subdomain returns a response" );
};

test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://someuser.example.org/profile";
    $cb->($req);

    is( $routed_uri, '/profile', "unknown subdomain does not rewrite URI" );
};
