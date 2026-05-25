#!/usr/bin/perl
#
# DW::RateLimit tests
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More tests => 111;
use Test::MockTime qw(set_fixed_time restore_time);

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test;
use DW::RateLimit;
use Time::HiRes qw(time);

# Test basic rate limit creation
{
    my $limit = DW::RateLimit->get( "test_key", rate => "10/60s" );
    ok( $limit, "Created rate limit object with rate string" );
    isa_ok( $limit, "DW::RateLimit::Limit" );
    is( $limit->{refill_rate}, 10 / 60, "Refill rate calculated correctly from rate string" );
}

# Test different rate string units
{
    my $limit = DW::RateLimit->get( "test_key", rate => "10/1m" );
    ok( $limit, "Created rate limit object with minutes" );
    is( $limit->{interval_secs}, 60, "Minutes converted to seconds correctly" );

    $limit = DW::RateLimit->get( "test_key", rate => "10/1h" );
    ok( $limit, "Created rate limit object with hours" );
    is( $limit->{interval_secs}, 3600, "Hours converted to seconds correctly" );

    $limit = DW::RateLimit->get( "test_key", rate => "10/1d" );
    ok( $limit, "Created rate limit object with days" );
    is( $limit->{interval_secs}, 86400, "Days converted to seconds correctly" );
}

# Test invalid rate strings
{
    my $limit = DW::RateLimit->get( "test_key", rate => "invalid" );
    ok( !$limit, "Invalid rate string rejected" );

    $limit = DW::RateLimit->get(
        "test_key",
        rate => "10/60"    # Missing unit
    );
    ok( !$limit, "Rate string without unit rejected" );

    $limit = DW::RateLimit->get(
        "test_key",
        rate => "10/60x"    # Invalid unit
    );
    ok( !$limit, "Rate string with invalid unit rejected" );
}

# Test missing rate parameter
{
    my $limit = DW::RateLimit->get("test_key");
    ok( !$limit, "Missing rate parameter rejected" );
}

# Test key generation
{
    my $limit = DW::RateLimit->get( "test_key", rate => "10/60s" );
    ok( $limit, "Created rate limit object for key generation test" );

    # Test key generation for user ID
    my $key = $limit->_get_key( userid => 123 );
    is( $key, "ratelimit::test_key:user:123", "Generated correct key for user ID" );

    # Test key generation for IP
    $key = $limit->_get_key( ip => "192.168.1.1" );
    is( $key, "ratelimit::test_key:ip:192.168.1.1", "Generated correct key for IP" );

    # Test key generation for both
    $key = $limit->_get_key( userid => 123, ip => "192.168.1.1" );
    is(
        $key,
        "ratelimit::test_key:user:123:ip:192.168.1.1",
        "Generated correct key for user ID and IP"
    );
}

# Test rate limit functionality
LJ::Test::with_fake_memcache {
    my $limit = DW::RateLimit->get( "test_key", rate => "2/60s" );

    # Test first request
    my $result = $limit->check( userid => 123 );
    ok( !$result->{exceeded}, "First request not exceeded" );
    is( $result->{count},          1, "Count incremented to 1" );
    is( $result->{time_remaining}, 0, "No time remaining when not exceeded" );

    # Test second request
    $result = $limit->check( userid => 123 );
    ok( !$result->{exceeded}, "Second request not exceeded" );
    is( $result->{count},          2, "Count incremented to 2" );
    is( $result->{time_remaining}, 0, "No time remaining when not exceeded" );

    # Test third request (should be exceeded)
    $result = $limit->check( userid => 123 );
    ok( $result->{exceeded}, "Third request exceeded" );
    is( $result->{count}, 2, "Count remains at 2 when exceeded" );
    ok( $result->{time_remaining} > 0, "Time remaining when exceeded" );
};

# Test leaky bucket refill behavior
LJ::Test::with_fake_memcache {
    my $limit = DW::RateLimit->get( "test_key", rate => "10/60s" );

    # Set initial time
    set_fixed_time(1000);

    # Use up all tokens
    for ( 1 .. 10 ) {
        my $result = $limit->check( userid => 123 );
        ok( !$result->{exceeded}, "Request $_ not exceeded" );
    }
    my $result = $limit->check( userid => 123 );
    ok( $result->{exceeded}, "Bucket empty, request exceeded" );
    is( $result->{count}, 10, "Count at max when exceeded" );
    is( $result->{time_remaining}, 60,
        "Time remaining is exactly 60 seconds when bucket is empty" );

    # Advance time by 30 seconds
    set_fixed_time(1030);

    # Should have 5 tokens available (half refilled)
    $result = $limit->check( userid => 123 );
    ok( !$result->{exceeded}, "Request after partial refill not exceeded" );
    is( $result->{count},          6, "Bucket partially refilled (5 tokens + 1 from check)" );
    is( $result->{time_remaining}, 0, "No time remaining when not exceeded" );

    # Use up the refilled tokens
    for ( 1 .. 4 ) {    # Only need 4 more since we already used one
        $result = $limit->check( userid => 123 );
        ok( !$result->{exceeded}, "Refilled request $_ not exceeded" );
    }
    $result = $limit->check( userid => 123 );
    ok( $result->{exceeded}, "Bucket empty again" );
    is( $result->{count}, 10, "Count at max when exceeded again" );
    is( $result->{time_remaining},
        60, "Time remaining is exactly 60 seconds when bucket is empty again" );

    # Restore real time
    restore_time();
};

# Test rate limit caching
LJ::Test::with_fake_memcache {
    my $limit1 = DW::RateLimit->get( "test_key", rate => "10/60s" );
    my $limit2 = DW::RateLimit->get( "test_key", rate => "10/60s" );

    # Test that we get the same object back by comparing properties
    is( $limit1->{name},      $limit2->{name},      "Rate limit objects have same name" );
    is( $limit1->{max_count}, $limit2->{max_count}, "Rate limit objects have same max_count" );
    is(
        $limit1->{interval_secs},
        $limit2->{interval_secs},
        "Rate limit objects have same interval_secs"
    );

    # Test that different parameters create new objects
    my $limit3 = DW::RateLimit->get(
        "test_key",
        rate => "20/60s"    # Different rate
    );
    isnt( $limit1->{max_count}, $limit3->{max_count},
        "Different parameters create new rate limit objects" );
};

# Test reset functionality
LJ::Test::with_fake_memcache {
    my $limit = DW::RateLimit->get( "test_key", rate => "10/60s" );

    # Set initial time
    set_fixed_time(1000);

    # Use up all tokens
    for ( 1 .. 10 ) {
        $limit->check( userid => 123 );
    }

    # Reset the counter
    $limit->reset( userid => 123 );
    my $result = $limit->check( userid => 123 );
    is( $result->{count},          1, "Count is 1 after reset (due to check consuming a token)" );
    is( $result->{time_remaining}, 0, "No time remaining after reset" );

    # Restore real time
    restore_time();
};

# Test configuration overrides
LJ::Test::with_fake_memcache {

    # Set up test configuration
    $LJ::RATE_LIMITS{test_override} = {
        rate => "5/30s",
        mode => 'ignore'
    };

    # Test that configuration is applied
    my $limit = DW::RateLimit->get(
        "test_override",
        rate => "10/60s"    # Should be overridden
    );
    ok( $limit, "Created rate limit object with overrides" );
    is( $limit->{max_count},     5,        "max_count overridden correctly" );
    is( $limit->{interval_secs}, 30,       "interval_secs overridden correctly" );
    is( $limit->{mode},          'ignore', "mode overridden correctly" );
    is( $limit->{refill_rate},   5 / 30,   "refill rate calculated with overridden values" );

    # Test ignore mode behavior
    my $result = $limit->check( userid => 123 );
    ok( !$result->{exceeded}, "Ignore mode: request not exceeded" );
    is( $result->{count},          0, "Ignore mode: count remains 0" );
    is( $result->{time_remaining}, 0, "Ignore mode: no time remaining" );

    # Test that multiple requests in ignore mode don't increment
    for ( 1 .. 10 ) {
        $result = $limit->check( userid => 123 );
        ok( !$result->{exceeded}, "Ignore mode: request $_ not exceeded" );
        is( $result->{count}, 0, "Ignore mode: count still 0 after request $_" );
    }

    # Test block mode (default)
    my $block_limit = DW::RateLimit->get( "test_block", rate => "2/60s" );
    is( $block_limit->{mode}, 'block', "Default mode is block" );

    # Test block mode behavior
    $result = $block_limit->check( userid => 123 );
    ok( !$result->{exceeded}, "Block mode: first request not exceeded" );
    is( $result->{count}, 1, "Block mode: count incremented" );

    $result = $block_limit->check( userid => 123 );
    ok( !$result->{exceeded}, "Block mode: second request not exceeded" );
    is( $result->{count}, 2, "Block mode: count incremented again" );

    $result = $block_limit->check( userid => 123 );
    ok( $result->{exceeded}, "Block mode: third request exceeded" );
    is( $result->{count}, 2, "Block mode: count capped at max" );
    ok( $result->{time_remaining} > 0, "Block mode: time remaining when exceeded" );

    # Clean up test configuration
    delete $LJ::RATE_LIMITS{test_override};
};

# Test IP exclusion (internal/private IPs skip rate limiting)
{
    # Default matcher: RFC1918 + loopback are excluded.
    ok( DW::RateLimit->ip_is_excluded("10.1.2.3"),       "10/8 excluded" );
    ok( DW::RateLimit->ip_is_excluded("172.16.5.5"),     "172.16/12 low end excluded" );
    ok( DW::RateLimit->ip_is_excluded("172.31.255.255"), "172.16/12 high end excluded" );
    ok( DW::RateLimit->ip_is_excluded("192.168.0.42"),   "192.168/16 excluded" );
    ok( DW::RateLimit->ip_is_excluded("127.0.0.1"),      "loopback excluded" );

    # Public and just-outside-boundary IPs are NOT excluded.
    ok( !DW::RateLimit->ip_is_excluded("8.8.8.8"),     "public 8.8.8.8 not excluded" );
    ok( !DW::RateLimit->ip_is_excluded("1.2.3.4"),     "public 1.2.3.4 not excluded" );
    ok( !DW::RateLimit->ip_is_excluded("172.32.0.1"),  "just above 172.16/12 not excluded" );
    ok( !DW::RateLimit->ip_is_excluded("11.0.0.1"),    "just above 10/8 not excluded" );
    ok( !DW::RateLimit->ip_is_excluded("169.254.1.1"), "link-local deliberately not excluded" );

    # Empty / undef IP is not excluded.
    ok( !DW::RateLimit->ip_is_excluded(undef), "undef IP not excluded" );
    ok( !DW::RateLimit->ip_is_excluded(""),    "empty IP not excluded" );

    # Operator override replaces the default matcher entirely.
    local $LJ::RATE_LIMIT_EXCLUDE_IP = sub { $_[0] eq "8.8.8.8" };
    ok( DW::RateLimit->ip_is_excluded("8.8.8.8"),   "override: 8.8.8.8 excluded" );
    ok( !DW::RateLimit->ip_is_excluded("10.1.2.3"), "override: default range no longer applies" );
}

# Test that the rate-limit middleware stashes auth + outcome hints in the PSGI env
# for the request-metrics tags.
LJ::Test::with_fake_memcache {
    require Plack::Middleware::DW::RateLimit;

    my $build_mw = sub {
        my $mw = Plack::Middleware::DW::RateLimit->new;
        $mw->app( sub { [ 200, [], ['ok'] ] } );
        return $mw;
    };

    no warnings 'redefine', 'once';

    # Anonymous request from an internal IP -> excluded; auth anon; limiter skipped.
    {
        local *LJ::get_remote    = sub { undef };
        local *LJ::get_remote_ip = sub { '10.0.0.5' };
        my %env;
        $build_mw->()->call( \%env );
        is( $env{'dw.stats.auth'},      'anon',     'excluded: auth tagged anon' );
        is( $env{'dw.stats.ratelimit'}, 'excluded', 'internal IP tagged excluded' );
    }

    # Anonymous request from a public IP, under the limit -> allowed.
    # reset() before checking so any earlier call in this block doesn't consume
    # a token and make the "allowed" assertion flaky.
    {
        local *LJ::get_remote    = sub { undef };
        local *LJ::get_remote_ip = sub { '203.0.113.7' };
        local $LJ::RATE_LIMITS{anonymous_requests} = { rate => '5/60s' };
        DW::RateLimit->get( 'anonymous_requests', rate => '5/60s' )->reset( ip => '203.0.113.7' );
        my %env;
        $build_mw->()->call( \%env );
        is( $env{'dw.stats.ratelimit'}, 'allowed', 'public IP under limit tagged allowed' );
    }

    # Anonymous request from a public IP, over the limit -> blocked + 429.
    {
        local *LJ::get_remote    = sub { undef };
        local *LJ::get_remote_ip = sub { '203.0.113.8' };
        local $LJ::RATE_LIMITS{anonymous_requests} = { rate => '1/60s' };
        DW::RateLimit->get( 'anonymous_requests', rate => '1/60s' )->reset( ip => '203.0.113.8' );
        my $mw = $build_mw->();
        $mw->call( {} );    # first request consumes the single token
        my %env2;
        my $res = $mw->call( \%env2 );    # second request is blocked
        is( $env2{'dw.stats.ratelimit'}, 'blocked', 'over limit tagged blocked' );
        is( $res->[0],                   429,       'blocked request returns 429' );
    }

    # Authenticated request -> auth tagged user.
    {
        my $fake_user = bless { userid => 42 }, 'LJ::User';
        local *LJ::get_remote    = sub { $fake_user };
        local *LJ::get_remote_ip = sub { '203.0.113.9' };
        local $LJ::RATE_LIMITS{authenticated_requests} = { rate => '5/60s' };
        my %env;
        $build_mw->()->call( \%env );
        is( $env{'dw.stats.auth'}, 'user', 'authenticated request tagged user' );
    }
};
