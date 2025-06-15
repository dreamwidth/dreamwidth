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

use LJ::MemCache;
use LJ::User;
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

# Get a rate limit object
sub get {
    my ( $class, $name, %opts ) = @_;

    # Validate required parameters
    return undef unless $name && $opts{max_count} && $opts{per_interval_secs};

    # Check for configuration overrides
    if ( $LJ::RATE_LIMITS{$name} ) {
        my $config = $LJ::RATE_LIMITS{$name};
        $opts{max_count}         = $config->{max_count} if defined $config->{max_count};
        $opts{per_interval_secs} = $config->{per_interval_secs}
            if defined $config->{per_interval_secs};
        $opts{mode} = $config->{mode} if defined $config->{mode};
    }

    return DW::RateLimit::Limit->new(
        name              => $name,
        max_count         => $opts{max_count},
        per_interval_secs => $opts{per_interval_secs},
        mode              => $opts{mode},
    );
}

1;
