#!/usr/bin/perl
#
# Plack::Middleware::DW::RateLimit
#
# Applies rate limiting to incoming requests. Authenticated users get a
# higher limit than anonymous users. Ported from the rate-limit checks in
# Apache::LiveJournal::trans().
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

package Plack::Middleware::DW::RateLimit;

use strict;
use v5.10;

use parent qw/ Plack::Middleware /;

use DW::RateLimit;

sub call {
    my ( $self, $env ) = @_;

    my $remote = LJ::get_remote();
    my $ip     = LJ::get_remote_ip();

    # Stash the auth state for the per-request metrics tags (read by DW::AccessLog).
    $env->{'dw.stats.auth'} = $remote ? 'user' : 'anon';

    # Internal infrastructure (e.g. load-balancer health checks) connects without a
    # trusted X-Forwarded-For, so its resolved IP is private. Skip rate limiting for
    # those entirely, regardless of auth state.
    if ( $ip && DW::RateLimit->ip_is_excluded($ip) ) {
        $env->{'dw.stats.ratelimit'} = 'excluded';
        return $self->app->($env);
    }

    # Get the appropriate rate limit based on whether user is logged in
    my $limit;
    if ($remote) {
        $limit = DW::RateLimit->get( "authenticated_requests", rate => "100/60s" );
    }
    else {
        $limit = DW::RateLimit->get( "anonymous_requests", rate => "30/60s" );
    }

    # Check if rate limit is exceeded
    if ($limit) {
        my $result = $limit->check(
            userid => $remote ? $remote->userid : undef,
            ip     => $remote ? undef           : $ip
        );

        $env->{'dw.stats.ratelimit'} = $result->{exceeded} ? 'blocked' : 'allowed';

        if ( $result->{exceeded} ) {
            my $retry_after = $result->{time_remaining};
            my $body =
                  "<h1>429 Too Many Requests</h1>"
                . "<p>You have made too many requests. Please try again later.</p>";
            $body .= "<p>Please wait $retry_after seconds before trying again.</p>"
                if $retry_after;

            return [
                429,
                [
                    'Content-Type' => 'text/html',
                    'Retry-After'  => $retry_after,
                ],
                [$body]
            ];
        }
    }

    return $self->app->($env);
}

1;
