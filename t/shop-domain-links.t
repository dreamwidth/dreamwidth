#!/usr/bin/perl
#
# t/shop-domain-links.t
#
# Test shop subdomain defaults, signup upgrade redirect, and off-domain shop
# redirect path preservation.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Controller::Create;
use DW::Controller::Shop;
use DW::Request;
use DW::Request::Plack;
use DW::Request::Standard;
use HTTP::Request;
use LJ::Test qw( temp_user );

sub _make_request {
    my ( $method, $url ) = @_;
    DW::Request->reset;
    my $req = HTTP::Request->new( $method => $url );
    $req->header( Host => $req->uri->host );
    my $r = DW::Request::Standard->new($req);
    return $r;
}

subtest 'signup upgrade redirects to SHOPROOT' => sub {
    my $u = temp_user();

    local $LJ::PROTOCOL           = 'https';
    local $LJ::DOMAIN             = 'example.org';
    local $LJ::DOMAIN_WEB         = 'www.example.org';
    local $LJ::DOMAIN_SHOP        = 'shop.example.org';
    local $LJ::SITEROOT           = 'https://www.example.org';
    local $LJ::SHOPROOT           = 'https://shop.example.org';
    local $LJ::DISABLED{payments} = 0;

    my $r = _make_request( POST => 'https://www.example.org/create/upgrade' );
    LJ::set_remote($u);
    DW::Controller::Create::upgrade_handler();
    is(
        $r->header_out('Location'),
        'https://shop.example.org/account?for=self',
        'POST /create/upgrade redirects directly to SHOPROOT/account?for=self'
    );

    local $LJ::DISABLED{payments} = 1;
    $r = _make_request( POST => 'https://www.example.org/create/upgrade' );
    LJ::set_remote($u);
    DW::Controller::Create::upgrade_handler();
    is(
        $r->header_out('Location'),
        'https://www.example.org/create/next',
        'POST /create/upgrade skips to /create/next when payments are disabled'
    );
};

subtest 'off-domain shop redirects preserve subpath and query string' => sub {
    local $LJ::PROTOCOL           = 'https';
    local $LJ::DOMAIN             = 'example.org';
    local $LJ::DOMAIN_WEB         = 'www.example.org';
    local $LJ::DOMAIN_SHOP        = 'shop.example.org';
    local $LJ::SITEROOT           = 'https://www.example.org';
    local $LJ::SHOPROOT           = 'https://shop.example.org';
    local $LJ::DISABLED{payments} = 0;

    my @cases = (
        [ 'https://www.example.org/shop',  'https://shop.example.org/' ],
        [ 'https://www.example.org/shop/', 'https://shop.example.org/' ],
        [
            'https://www.example.org/shop/account?for=self',
            'https://shop.example.org/account?for=self'
        ],
        [ 'https://www.example.org/shop/history',   'https://shop.example.org/history' ],
        [ 'https://www.example.org/shop?newcart=1', 'https://shop.example.org/?newcart=1' ],
        [
            'https://www.example.org/shop//evil.example/x',
            'https://shop.example.org/evil.example/x'
        ],
    );

    foreach my $case (@cases) {
        my ( $url, $expected ) = @$case;
        my $r = _make_request( GET => $url );
        my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller( anonymous => 1 );
        is( $ok,                        0,         "off-domain $url stops controller" );
        is( $r->header_out('Location'), $expected, "off-domain $url redirects to $expected" );
    }

    {
        local $LJ::SHOPROOT = 'https://shop.example.org/';
        my $r = _make_request( GET => 'https://www.example.org/shop/points?for=self' );
        my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller( anonymous => 1 );
        is( $ok, 0, 'off-domain request stops controller with trailing-slash SHOPROOT' );
        is(
            $r->header_out('Location'),
            'https://shop.example.org/points?for=self',
            'trailing slash on SHOPROOT does not produce double slash'
        );
    }

    {
        DW::Request->reset;
        my $r = DW::Request::Plack->new(
            {
                REQUEST_METHOD => 'GET',
                HTTP_HOST      => 'www.example.org',
                PATH_INFO      => '/shop/foo?bar',
                QUERY_STRING   => '',
            }
        );
        my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller( anonymous => 1 );
        is( $ok, 0, 'off-domain Plack request with decoded ? stops controller' );
        is(
            $r->header_out('Location'),
            'https://shop.example.org/foo%3Fbar',
            'decoded ? in Plack path_info is re-escaped instead of becoming a query string'
        );
    }

    {
        my $r = _make_request( GET => 'https://shop.example.org/shop/account?for=self' );
        my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller( anonymous => 1 );
        is( $ok, 1, 'request on DOMAIN_SHOP proceeds without redirecting' );
        is( $r->header_out('Location'), undef, 'no redirect header set on DOMAIN_SHOP' );
    }

    {
        my $r = _make_request( GET => 'https://SHOP.EXAMPLE.ORG/shop/account?for=self' );
        my ( $ok, $rv ) = DW::Controller::Shop::_shop_controller( anonymous => 1 );
        is( $ok, 1, 'uppercase DOMAIN_SHOP host proceeds without redirecting' );
    }
};

subtest 'register_standard_resources skips jQuery case-insensitively on DOMAIN_SHOP' => sub {
    local $LJ::DOMAIN_WEB  = 'www.example.org';
    local $LJ::DOMAIN_SHOP = 'shop.example.org';

    foreach my $case (
        [ 'www.example.org',  1, 'main web host loads jQuery' ],
        [ 'shop.example.org', 0, 'lowercase DOMAIN_SHOP skips jQuery' ],
        [ 'SHOP.EXAMPLE.ORG', 0, 'uppercase DOMAIN_SHOP skips jQuery' ],
        )
    {
        my ( $host, $expect_jquery, $label ) = @$case;
        local @LJ::NEEDED_RES;
        local %LJ::NEEDED_RES;
        DW::Request->reset;
        DW::Request::Plack->new(
            {
                REQUEST_METHOD => 'GET',
                HTTP_HOST      => $host,
                PATH_INFO      => '/shop',
                QUERY_STRING   => '',
            }
        );
        LJ::register_standard_resources();
        my $has_jquery = $LJ::NEEDED_RES{'foundation-js/jquery/jquery-1.8.3.js'} ? 1 : 0;
        is( $has_jquery, $expect_jquery, $label );
    }
};

subtest 'Defaults.pm derives SHOPROOT from separate DOMAIN_SHOP' => sub {
    my $defaults = "$ENV{LJHOME}/cgi-bin/LJ/Global/Defaults.pm";

    {
        local $LJ::IS_DEV_SERVER     = 0;
        local $LJ::IS_DEV_CONTAINER  = 0;
        local $LJ::PROTOCOL          = undef;
        local $LJ::DOMAIN            = 'example.org';
        local $LJ::DOMAIN_WEB        = undef;
        local $LJ::DOMAIN_SHOP       = 'shop.example.org';
        local $LJ::SITEROOT          = undef;
        local $LJ::SHOPROOT          = undef;
        local $LJ::RELATIVE_SITEROOT = undef;

        ok( do $defaults, 'loaded Defaults.pm with separate DOMAIN_SHOP' ) or diag $@;
        is( $LJ::SHOPROOT, 'https://shop.example.org',
            'SHOPROOT defaults to PROTOCOL://DOMAIN_SHOP when DOMAIN_SHOP != DOMAIN_WEB' );
    }

    {
        local $LJ::IS_DEV_SERVER     = 0;
        local $LJ::IS_DEV_CONTAINER  = 0;
        local $LJ::PROTOCOL          = undef;
        local $LJ::DOMAIN            = 'example.org';
        local $LJ::DOMAIN_WEB        = undef;
        local $LJ::DOMAIN_SHOP       = undef;
        local $LJ::SITEROOT          = undef;
        local $LJ::SHOPROOT          = undef;
        local $LJ::RELATIVE_SITEROOT = undef;

        ok( do $defaults, 'loaded Defaults.pm with default DOMAIN_SHOP' ) or diag $@;
        is( $LJ::DOMAIN_SHOP, 'www.example.org', 'DOMAIN_SHOP defaults to DOMAIN_WEB' );
        is(
            $LJ::SHOPROOT,
            'https://www.example.org/shop',
            'SHOPROOT defaults to PROTOCOL://DOMAIN_WEB/shop when DOMAIN_SHOP == DOMAIN_WEB'
        );
    }

    {
        local $LJ::IS_DEV_SERVER     = 0;
        local $LJ::IS_DEV_CONTAINER  = 0;
        local $LJ::PROTOCOL          = undef;
        local $LJ::DOMAIN            = 'example.org';
        local $LJ::DOMAIN_WEB        = undef;
        local $LJ::DOMAIN_SHOP       = 'shop.example.org';
        local $LJ::SITEROOT          = undef;
        local $LJ::SHOPROOT          = 'https://custom.example.org/store';
        local $LJ::RELATIVE_SITEROOT = undef;

        ok( do $defaults, 'loaded Defaults.pm with explicit SHOPROOT' ) or diag $@;
        is( $LJ::SHOPROOT, 'https://custom.example.org/store', 'explicit SHOPROOT is preserved' );
    }
};

done_testing();
