#!/usr/bin/perl
# t/plack-sysban.t
#
# Tests for the Plack sysban blocking middleware (Plack::Middleware::DW::Sysban).
# Uses mocking to simulate sysban checks without requiring memcache/DB.
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
        plan skip_all => "Plack::Test required for sysban tests";
    };
}

plan tests => 15;

# Load the Plack app
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Mock state: these control what the mocked functions return
my %mock_ip_bans;
my %mock_noanon_ip_bans;
my %mock_uniq_bans;
my $mock_tempban = 0;
my $mock_remote  = undef;
my @mock_uniq_cookie;

{
    no warnings 'redefine', 'once';

    # Mock routing so requests that pass through sysban return 200.
    # Return 0 to signal "handled" — returning undef falls through to BML.
    *DW::Routing::call = sub {
        my ( $class, %args ) = @_;
        my $r = DW::Request->get;
        $r->status(200);
        $r->print('OK');
        return 0;
    };

    *LJ::sysban_check = sub {
        my ( $what, $value ) = @_;
        return $mock_ip_bans{$value}        if $what eq 'ip';
        return $mock_noanon_ip_bans{$value} if $what eq 'noanon_ip';
        return $mock_uniq_bans{$value}      if $what eq 'uniq';
        return 0;
    };

    *LJ::Sysban::tempban_check = sub {
        return $mock_tempban;
    };

    *LJ::get_remote = sub {
        return $mock_remote;
    };

    *LJ::UniqCookie::parts_from_cookie = sub {
        return @mock_uniq_cookie;
    };

    # Disable middleware concerns not under test
    *LJ::Session::session_from_cookies   = sub { return undef };
    *LJ::UniqCookie::ensure_cookie_value = sub { return };
    *LJ::User::Login::get_remote         = sub { return $mock_remote };
    *DW::RateLimit::get                  = sub { return undef };
}

# Helper to reset all mocks
sub reset_mocks {
    %mock_ip_bans        = ();
    %mock_noanon_ip_bans = ();
    %mock_uniq_bans      = ();
    $mock_tempban        = 0;
    $mock_remote         = undef;
    @mock_uniq_cookie    = ();
}

# Test 1: Normal request passes through
reset_mocks();
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    is( $res->code, 200, "Normal request passes through sysban" );
};

# Test 2: IP-banned request returns 403
reset_mocks();
$mock_ip_bans{'127.0.0.1'} = 1;
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    is( $res->code, 403, "IP-banned request returns 403" );
};

# Test 3: IP ban response contains blocked message
reset_mocks();
$mock_ip_bans{'127.0.0.1'} = 1;
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    like( $res->content, qr/403 Denied/, "IP ban response contains denied message" );
};

# Test 4: Tempban returns 403
reset_mocks();
$mock_tempban = 1;
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    is( $res->code, 403, "Tempbanned request returns 403" );
};

# Test 5: Uniq cookie ban returns 403
reset_mocks();
@mock_uniq_cookie = ( 'baduniq123', time(), '' );
$mock_uniq_bans{baduniq123} = 1;
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    is( $res->code, 403, "Uniq-banned request returns 403" );
};

# Test 6: Uniq cookie present but not banned passes through
reset_mocks();
@mock_uniq_cookie = ( 'gooduniq456', time(), '' );
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    is( $res->code, 200, "Uniq cookie present but not banned passes through" );
};

# Test 7: noanon_ip ban blocks anonymous user
reset_mocks();
$mock_remote = undef;
$mock_noanon_ip_bans{'127.0.0.1'} = 1;
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    is( $res->code, 403, "noanon_ip ban blocks anonymous user" );
};

# Test 8: noanon_ip ban response contains login link
reset_mocks();
$mock_remote = undef;
$mock_noanon_ip_bans{'127.0.0.1'} = 1;
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    like( $res->content, qr{/login}, "noanon_ip ban response contains login link" );
};

# Test 9: noanon_ip ban does NOT block logged-in user
reset_mocks();
$mock_remote = 1;
$mock_noanon_ip_bans{'127.0.0.1'} = 1;
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    is( $res->code, 200, "noanon_ip ban does not block logged-in user" );
};

# Test 10: noanon_ip ban allows /login path for anonymous user
reset_mocks();
$mock_remote = undef;
$mock_noanon_ip_bans{'127.0.0.1'} = 1;
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/login" );

    is( $res->code, 200, "noanon_ip ban allows /login for anonymous user" );
};

# Tests 11-12: X-Forwarded-For hops that are our own trusted proxies (CDN
# edges, the load balancer) are not checked against IP bans -- a ban on a CDN
# server would otherwise block everyone routed through it -- while the client
# hop still is.
{
    local $LJ::TRUST_X_HEADERS  = 1;
    local $LJ::IS_TRUSTED_PROXY = sub { $_[0] eq '127.0.0.1' || $_[0] eq '198.51.100.7' };

    reset_mocks();
    $mock_ip_bans{'198.51.100.7'} = 1;
    test_psgi $app, sub {
        my $cb  = shift;
        my $res = $cb->( GET "/", 'X-Forwarded-For' => '203.0.113.5, 198.51.100.7' );

        is( $res->code, 200, "IP ban on a trusted proxy hop does not block its clients" );
    };

    reset_mocks();
    $mock_ip_bans{'203.0.113.5'} = 1;
    test_psgi $app, sub {
        my $cb  = shift;
        my $res = $cb->( GET "/", 'X-Forwarded-For' => '203.0.113.5, 198.51.100.7' );

        is( $res->code, 403, "IP ban on the client behind a trusted proxy still blocks" );
    };
}

# Tests 13-15: CDN proxies ($LJ::IS_CDN_PROXY) are trusted only when the
# request carries the shared secret header. Other customers of the same CDN
# can route requests to us with any X-Forwarded-For, but not the secret, so
# for them the CDN server itself counts as the client.
{
    local $LJ::TRUST_X_HEADERS  = 1;
    local $LJ::IS_TRUSTED_PROXY = sub { $_[0] eq '127.0.0.1' };
    local $LJ::IS_CDN_PROXY     = sub { $_[0] eq '198.51.100.20' };
    local $LJ::CDN_PROXY_SECRET = 'test-secret';
    my @xff = ( 'X-Forwarded-For' => '203.0.113.5, 198.51.100.20' );

    reset_mocks();
    $mock_ip_bans{'198.51.100.20'} = 1;
    test_psgi $app, sub {
        my $cb  = shift;
        my $res = $cb->( GET "/", @xff, 'X-DW-WAF-Bypass' => 'test-secret' );

        is( $res->code, 200, "CDN hop with the secret is trusted, so its ban is skipped" );
    };

    reset_mocks();
    $mock_ip_bans{'198.51.100.20'} = 1;
    test_psgi $app, sub {
        my $cb  = shift;
        my $res = $cb->( GET "/", @xff );

        is( $res->code, 403, "CDN hop without the secret is treated as the client" );
    };

    reset_mocks();
    $mock_ip_bans{'198.51.100.20'} = 1;
    test_psgi $app, sub {
        my $cb  = shift;
        my $res = $cb->( GET "/", @xff, 'X-DW-WAF-Bypass' => 'wrong' );

        is( $res->code, 403, "CDN hop with the wrong secret is treated as the client" );
    };
}
