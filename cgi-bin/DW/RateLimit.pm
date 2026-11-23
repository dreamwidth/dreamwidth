#!/usr/bin/perl
#
# DW::Request::RateLimit
#
# Module to handle rate limiting for the site using a leaky bucket algorithm.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::RateLimit;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::Request;
use LJ::MemCache;
use LJ::User;
use Net::Subnet;
use Time::HiRes qw(time);

# Class to handle rate limiting
package DW::RateLimit::Limit;

use strict;
use warnings;

sub new {
    my ( $class, %opts ) = @_;
    my $self = bless {
        name          => $opts{name},
        max_count     => $opts{max_count},
        interval_secs => $opts{per_interval_secs},
        key_prefix    => "ratelimit:",
        mode          => $opts{mode} || 'block',

        # Calculate refill rate (tokens per second)
        refill_rate => $opts{max_count} / $opts{per_interval_secs},
    }, $class;
    return $self;
}

# Check the rate limit status
# Returns a hash containing:
#   exceeded: 1 if they have exceeded the limit, 0 if they haven't
#   time_remaining: seconds until the rate limit resets (0 if not exceeded)
#   count: current count of requests
sub check {
    my ( $self, %opts ) = @_;

    # Handle ignore mode - always return not exceeded
    return { exceeded => 0, time_remaining => 0, count => 0 } if $self->{mode} eq 'ignore';

    # Get the key to use for this rate limit
    my $key = $self->_get_key(%opts);
    return { exceeded => 0, time_remaining => 0, count => 0 } unless $key;

    # Get the current state from memcache
    my $state_str = LJ::MemCache::get($key);
    my ( $level, $last_update );
    if ($state_str) {
        ( $level, $last_update ) = split( ':', $state_str );
    }
    else {
        $level       = $self->{max_count};
        $last_update = time();
    }

    # Calculate time elapsed since last update
    my $now     = time();
    my $elapsed = $now - $last_update;

    # Calculate new bucket level after refill
    my $new_level = $level + ( $elapsed * $self->{refill_rate} );
    $new_level = $self->{max_count} if $new_level > $self->{max_count};

    # Calculate current count (tokens used)
    my $count = $self->{max_count} - $new_level;

    # If we're at or over the limit
    if ( $new_level < 1 ) {

        # Log if in log mode
        if ( $self->{mode} eq 'log' ) {
            $log->info("RateLimit: Exceeded limit on $key");
            return { exceeded => 0, time_remaining => 0, count => $count };
        }

        # Calculate time remaining until reset
        # When bucket is empty, time remaining is the full interval
        my $time_remaining = $self->{interval_secs};
        return { exceeded => 1, time_remaining => $time_remaining, count => $count };
    }

    # Decrement the counter and update timestamp
    $new_level -= 1;
    my $new_state_str = "$new_level:$now";

    # Store the new state
    LJ::MemCache::set( $key, $new_state_str, $self->{interval_secs} );

    # Return success with no time remaining
    return { exceeded => 0, time_remaining => 0, count => $count + 1 };
}

# Reset the counter for this rate limit
sub reset {
    my ( $self, %opts ) = @_;

    # In ignore mode, do nothing
    return 1 if $self->{mode} eq 'ignore';

    my $key = $self->_get_key(%opts);
    return 0 unless $key;

    # Set the state to full bucket and current time
    my $new_state_str = "$self->{max_count}:" . time();

    # Store the new state with the full interval
    LJ::MemCache::set( $key, $new_state_str, $self->{interval_secs} );
    return 1;
}

# Internal method to generate the memcache key
sub _get_key {
    my ( $self, %opts ) = @_;

    my @key_parts = ( $self->{key_prefix}, $self->{name} );

    # Add userid if provided
    if ( my $userid = $opts{userid} ) {
        push @key_parts, "user:$userid";
    }

    # Add IP if provided
    if ( my $ip = $opts{ip} ) {
        push @key_parts, "ip:$ip";
    }

    # Add any additional identifiers
    if ( my $identifiers = $opts{identifiers} ) {
        foreach my $id ( sort keys %$identifiers ) {
            push @key_parts, "$id:$identifiers->{$id}";
        }
    }

    return join( ":", @key_parts );
}

# Package methods for DW::RateLimit
package DW::RateLimit;

use strict;
use warnings;

# Parse a rate limit string in the format "count/interval[unit]"
# Examples: "1/5s", "10/1m", "100/1h", "1000/1d"
sub _parse_rate_string {
    my ( $class, $rate_string ) = @_;
    return undef unless $rate_string && $rate_string =~ /^(\d+)\/(\d+)([smhd])$/;

    my ( $max_count, $interval, $unit ) = ( $1, $2, $3 );

    # Convert interval to seconds based on unit
    my $per_interval_secs = $interval;
    $per_interval_secs *= 60    if $unit eq 'm';
    $per_interval_secs *= 3600  if $unit eq 'h';
    $per_interval_secs *= 86400 if $unit eq 'd';

    return {
        max_count         => $max_count,
        per_interval_secs => $per_interval_secs
    };
}

# Get a rate limit object
sub get {
    my ( $class, $name, %opts ) = @_;

    # Validate required parameters
    return undef unless $name && $opts{rate};

    # Parse the rate string
    my $parsed = $class->_parse_rate_string( $opts{rate} );
    return undef unless $parsed;

    # Check for configuration overrides
    if ( $LJ::RATE_LIMITS{$name} ) {
        my $config = $LJ::RATE_LIMITS{$name};

        # Handle rate string in config
        if ( $config->{rate} ) {
            my $config_parsed = $class->_parse_rate_string( $config->{rate} );
            if ($config_parsed) {
                $parsed = $config_parsed;
            }
        }
        $opts{mode} = $config->{mode} if defined $config->{mode};
    }

    return DW::RateLimit::Limit->new(
        name              => $name,
        max_count         => $parsed->{max_count},
        per_interval_secs => $parsed->{per_interval_secs},
        mode              => $opts{mode},
    );
}

# The site-wide per-request limits: logged-in users are limited per user,
# everyone else per IP.
sub request_limit {
    my ( $class, $authenticated ) = @_;
    return $authenticated
        ? $class->get( "authenticated_requests", rate => "100/60s" )
        : $class->get( "anonymous_requests",     rate => "30/60s" );
}

# Body of the 429 response for a request over its limit.
sub blocked_body {
    my ( $class, $retry_after ) = @_;
    my $body =
          "<h1>429 Too Many Requests</h1>"
        . "<p>You have made too many requests. Please try again later.</p>";
    $body .= "<p>Please wait $retry_after seconds before trying again.</p>"
        if $retry_after;
    return $body;
}

# Protocol requests (XML-RPC and flat) carry their credentials in the request
# body, so the middleware can't tell who is calling. It defers them to the
# protocol, which charges each one exactly once, as soon as it knows: to the
# user's bucket once authentication succeeds, to the per-IP challenge bucket for
# getchallenge, and to the anonymous per-IP bucket otherwise. Anything the
# protocol doesn't charge is charged as anonymous when the request finishes.

# Called by the middleware: start deferring this request. Returns the state.
sub defer_protocol_request {
    my ( $class, $ip ) = @_;
    my $state = { ip => $ip, charged => 0, retry_after => 0 };
    my $r     = DW::Request->get;
    $r->pnote( ratelimit_protocol => $state ) if $r;
    return $state;
}

# Charge the current request if it was deferred and hasn't been charged yet.
# Pass user => $u once authenticated, or challenge => 1 for getchallenge;
# otherwise it is charged as anonymous. Returns the Retry-After seconds if the
# request is over its limit, or 0.
sub charge_protocol_request {
    my ( $class, %opts ) = @_;
    my $state = $opts{state};
    unless ($state) {
        my $r = DW::Request->get or return 0;
        $state = $r->pnote('ratelimit_protocol') or return 0;
    }
    return $state->{retry_after} if $state->{charged};
    $state->{charged} = 1;

    my $u = $opts{user};
    my $limit =
          $opts{challenge}
        ? $class->get( "protocol_challenges", rate => "100/60s" )
        : $class->request_limit( $u ? 1 : 0 );
    return 0 unless $limit;

    my $result = $limit->check(
        userid => $u ? $u->userid : undef,
        ip     => $u ? undef      : $state->{ip}
    );
    $state->{retry_after} = $result->{exceeded} ? $result->{time_remaining} || 1 : 0;
    return $state->{retry_after};
}

# Retry-After seconds if the current deferred request was charged over its
# limit, else 0. The protocol endpoints use this to answer with a 429.
sub protocol_retry_after {
    my ($class) = @_;
    my $r = DW::Request->get or return 0;
    my $state = $r->pnote('ratelimit_protocol') or return 0;
    return $state->{retry_after};
}

# Replace the response on $r with a 429.
sub print_blocked {
    my ( $class, $r, $retry_after ) = @_;
    $r->status(429);
    $r->header_out( 'Retry-After' => $retry_after );
    $r->content_type('text/html');
    $r->print( $class->blocked_body($retry_after) );
}

# Memoized default matcher: RFC1918 + loopback. Link-local (169.254/16) is
# intentionally excluded.
my $_default_internal_matcher;

sub _default_internal_matcher {
    $_default_internal_matcher ||= subnet_matcher qw(
        10.0.0.0/8
        172.16.0.0/12
        192.168.0.0/16
        127.0.0.0/8
    );
    return $_default_internal_matcher;
}

# Returns true if rate limiting should be skipped for this IP (i.e. the IP is
# internal infrastructure such as the load balancer issuing health checks).
# Honors $LJ::RATE_LIMIT_EXCLUDE_IP (a subnet_matcher / coderef) when set, else
# falls back to the default RFC1918 + loopback matcher.
sub ip_is_excluded {
    my ( $class, $ip ) = @_;
    return 0 unless defined $ip && length $ip;

    if ( ref $LJ::RATE_LIMIT_EXCLUDE_IP eq 'CODE' ) {
        return $LJ::RATE_LIMIT_EXCLUDE_IP->($ip) ? 1 : 0;
    }

    return _default_internal_matcher()->($ip) ? 1 : 0;
}

1;
