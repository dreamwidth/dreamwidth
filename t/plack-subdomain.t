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

plan tests => 32;

# Load the Plack app
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Stub routing and journal rendering so we can observe what reaches the app
my $routed_uri;
my $routed_username;
my ( $journal_render_user, $journal_render_uri );
{
    no warnings 'redefine', 'once';

    *DW::Routing::call = sub {
        my ( $class, %args ) = @_;
        $routed_uri      = $args{uri} || '';
        $routed_username = $args{username};

        # When username is passed, use 'user' role — app-only routes like
        # the homepage (/) don't match, so return undef to let journal
        # rendering handle it.  This mirrors real DW::Routing behavior.
        if ( $args{username} ) {
            return undef;
        }

        my $r = DW::Request->get;
        $r->status(200);
        $r->header_out( 'Content-Type' => 'text/plain' );
        $r->print("routed:$routed_uri");
        return;
    };

    *DW::Controller::Journal::render = sub {
        my ( $class, %args ) = @_;
        $journal_render_user = $args{user};
        $journal_render_uri  = $args{uri};
        my $r = DW::Request->get;
        $r->status(200);
        $r->header_out( 'Content-Type' => 'text/plain' );
        $r->print("journal:$journal_render_user:$journal_render_uri");
        return $r->res;
    };
}

# Configure subdomain functions for testing
local $LJ::USER_DOMAIN        = 'example.org';
local $LJ::DOMAIN_WEB         = 'www.example.org';
local $LJ::DOMAIN             = 'example.org';
local $LJ::SITEROOT           = 'https://www.example.org';
local $LJ::PROTOCOL           = 'https';
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

# --- User journal subdomain (no SUBDOMAIN_FUNCTION entry) ---

# Test 17-18: username.example.org renders journal
test_psgi $app, sub {
    my $cb = shift;
    $journal_render_user = undef;
    my $req = GET "http://someuser.example.org/2026/01/01/hello";
    my $res = $cb->($req);

    is( $res->code, 200, "journal subdomain returns 200" );
};

test_psgi $app, sub {
    my $cb = shift;
    $journal_render_user = undef;
    $journal_render_uri  = undef;
    my $req = GET "http://someuser.example.org/2026/01/01/hello";
    $cb->($req);

    is( $journal_render_user, 'someuser', "journal subdomain passes username to render" );
};

# Test 19: journal subdomain passes path to render
test_psgi $app, sub {
    my $cb = shift;
    $journal_render_uri = undef;
    my $req = GET "http://someuser.example.org/2026/01/01/hello";
    $cb->($req);

    is( $journal_render_uri, '/2026/01/01/hello', "journal subdomain passes path to render" );
};

# Test 20: journal subdomain root
test_psgi $app, sub {
    my $cb = shift;
    $journal_render_uri = undef;
    my $req = GET "http://someuser.example.org/";
    $cb->($req);

    is( $journal_render_uri, '/', "journal subdomain root passes / to render" );
};

# --- "journal" SUBDOMAIN_FUNCTION (community, users, syndicated) ---

# Test 21-22: journal function extracts user from path
{
    local %LJ::SUBDOMAIN_FUNCTION = ( community => 'journal' );

    test_psgi $app, sub {
        my $cb = shift;
        $journal_render_user = undef;
        $journal_render_uri  = undef;
        my $req = GET "http://community.example.org/examplecomm/profile";
        $cb->($req);

        is( $journal_render_user, 'examplecomm', "journal function extracts username from path" );
    };

    test_psgi $app, sub {
        my $cb = shift;
        $journal_render_uri = undef;
        my $req = GET "http://community.example.org/examplecomm/profile";
        $cb->($req);

        is( $journal_render_uri, '/profile', "journal function extracts path after username" );
    };
}

# --- "normal" SUBDOMAIN_FUNCTION ---

# Test 23-24: normal function passes through to app as-is
{
    local %LJ::SUBDOMAIN_FUNCTION = ( somefunc => 'normal' );

    test_psgi $app, sub {
        my $cb = shift;
        $routed_uri = undef;
        my $req = GET "http://somefunc.example.org/index";
        $cb->($req);

        is( $routed_uri, '/index', "normal function passes URI through unchanged" );
    };

    test_psgi $app, sub {
        my $cb  = shift;
        my $req = GET "http://somefunc.example.org/index";
        my $res = $cb->($req);

        is( $res->code, 200, "normal function returns 200" );
    };
}

# --- changehost SUBDOMAIN_FUNCTION ---

# Test 25-26: changehost redirects to new host
{
    local %LJ::SUBDOMAIN_FUNCTION = ( old => [ 'changehost', 'new.example.com' ] );

    test_psgi $app, sub {
        my $cb  = shift;
        my $req = GET "http://old.example.org/some/path";
        my $res = $cb->($req);

        is( $res->code, 303, "changehost returns redirect" );
    };

    test_psgi $app, sub {
        my $cb  = shift;
        my $req = GET "http://old.example.org/some/path";
        my $res = $cb->($req);

        is(
            $res->header('Location'),
            'https://new.example.com/some/path',
            "changehost redirects to correct host"
        );
    };
}

# --- Username passed to routing for journal subdomains ---

# Test 27: routing receives username for journal subdomains
test_psgi $app, sub {
    my $cb = shift;
    $routed_username = undef;
    my $req = GET "http://someuser.example.org/2026/01/01/hello";
    $cb->($req);

    is( $routed_username, 'someuser', "routing receives username for journal subdomain" );
};

# Test 28: routing receives no username for main domain
test_psgi $app, sub {
    my $cb = shift;
    $routed_username = 'should-be-cleared';
    my $req = GET "http://www.example.org/some/page";
    $cb->($req);

    is( $routed_username, undef, "routing receives no username for main domain" );
};

# Test 29-30: journal subdomain root URI renders journal, not homepage
test_psgi $app, sub {
    my $cb = shift;
    $journal_render_user = undef;
    my $req = GET "http://someuser.example.org/";
    $cb->($req);

    is( $journal_render_user, 'someuser',
        "journal subdomain root URI renders journal (not homepage)" );
};

test_psgi $app, sub {
    my $cb = shift;
    $routed_username = undef;
    my $req = GET "http://someuser.example.org/";
    $cb->($req);

    is( $routed_username, 'someuser', "journal subdomain root URI passes username to routing" );
};

# Test 31-32: main domain root URI renders homepage, not journal
test_psgi $app, sub {
    my $cb = shift;
    $journal_render_user = undef;
    my $req = GET "http://www.example.org/";
    my $res = $cb->($req);

    is( $journal_render_user, undef, "main domain root URI does not render journal" );
};

test_psgi $app, sub {
    my $cb  = shift;
    my $req = GET "http://www.example.org/";
    my $res = $cb->($req);

    like( $res->content, qr/^routed:/, "main domain root URI routes to homepage" );
};
