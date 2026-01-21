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

use Test::More tests => 91;
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
