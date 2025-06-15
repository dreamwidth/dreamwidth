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

use Test::More tests => 44;
use Test::MockTime qw(set_fixed_time restore_time);

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Test;
use DW::RateLimit;
use Time::HiRes qw(time);

# Test basic rate limit creation
{
    my $limit = DW::RateLimit->get(
        "test_key",
        max_count         => 10,
        per_interval_secs => 60
    );
    ok( $limit, "Created rate limit object" );
    isa_ok( $limit, "DW::RateLimit::Limit" );
    is( $limit->{refill_rate}, 10 / 60, "Refill rate calculated correctly" );
}

# Test key generation
{
    my $limit = DW::RateLimit->get(
        "test_key",
        max_count         => 10,
        per_interval_secs => 60
    );

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
    my $limit = DW::RateLimit->get(
        "test_key",
        max_count         => 2,
        per_interval_secs => 60
    );

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
    my $limit = DW::RateLimit->get(
        "test_key",
        max_count         => 10,
        per_interval_secs => 60
    );

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
    my $limit1 = DW::RateLimit->get(
        "test_key",
        max_count         => 10,
        per_interval_secs => 60
    );
    my $limit2 = DW::RateLimit->get(
        "test_key",
        max_count         => 10,
        per_interval_secs => 60
    );

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
        max_count         => 20,    # Different max_count
        per_interval_secs => 60
    );
    isnt( $limit1->{max_count}, $limit3->{max_count},
        "Different parameters create new rate limit objects" );
};

# Test reset functionality
LJ::Test::with_fake_memcache {
    my $limit = DW::RateLimit->get(
        "test_key",
        max_count         => 10,
        per_interval_secs => 60
    );

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
