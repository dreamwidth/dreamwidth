#!/usr/bin/perl
#
# DW::API::RateLimit
#
# API-specific rate limiting wrapper that uses DW::RateLimit
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

package DW::API::RateLimit;

use strict;
use warnings;
use JSON;

use DW::RateLimit;
use DW::Request;

# Wrap a function with rate limiting
sub wrap {
    my ( $class, $code, %opts ) = @_;

    # Validate required parameters
    return $code unless $opts{rate};

    # Create a rate limit object
    my $limit = DW::RateLimit->get(
        "api:" . ( $opts{name} || "unknown" ),
        rate => $opts{rate},
        mode => $opts{mode}
    );

    # Return a wrapped function that checks rate limits before executing
    return sub {
        my ( $self, $args ) = @_;

        # Get the request object
        my $r = DW::Request->get;
        return $code->( $self, $args ) unless $r;

        # Check rate limit
        my $result = $limit->check(
            userid => $args->{user} ? $args->{user}->userid : undef,
            ip     => $r->connection->remote_ip
        );

        if ( $result->{exceeded} ) {
            $r->status(429);
            $r->headers_out->{'Retry-After'} = $result->{time_remaining};
            $r->print(
                to_json(
                    {
                        success     => 0,
                        error       => "Rate limit exceeded",
                        retry_after => $result->{time_remaining}
                    }
                )
            );
            return;
        }

        # Execute the original function
        return $code->( $self, $args );
    };
}

1;
