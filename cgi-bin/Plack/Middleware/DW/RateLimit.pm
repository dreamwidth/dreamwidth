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

# Paths routed to the XML-RPC and flat protocol handlers (any extension
# routes there too).
my $PROTOCOL_PATH = qr!^/interface/(?:xmlrpc|flat)(?:\.[a-z]+)?$!;

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

    # Protocol clients authenticate in the request body, so without a session
    # cookie they look anonymous here. Defer them to the protocol, which charges
    # them per user once authenticated (see DW::RateLimit). A coarser per-IP
    # limit still applies up front, bounding the work an unauthenticated caller
    # can cause before the protocol charges it.
    return $self->_call_protocol( $env, $ip )
        if !$remote && ( $env->{PATH_INFO} // '' ) =~ $PROTOCOL_PATH;

    # Get the appropriate rate limit based on whether user is logged in
    my $limit = DW::RateLimit->request_limit( $remote ? 1 : 0 );

    # Check if rate limit is exceeded
    if ($limit) {
        my $result = $limit->check(
            userid => $remote ? $remote->userid : undef,
            ip     => $remote ? undef           : $ip
        );

        $env->{'dw.stats.ratelimit'} = $result->{exceeded} ? 'blocked' : 'allowed';

        return _blocked( $result->{time_remaining} ) if $result->{exceeded};
    }

    return $self->app->($env);
}

sub _call_protocol {
    my ( $self, $env, $ip ) = @_;

    my $limit = DW::RateLimit->get( "protocol_requests", rate => "300/60s" );
    if ($limit) {
        my $result = $limit->check( ip => $ip );
        if ( $result->{exceeded} ) {
            $env->{'dw.stats.ratelimit'} = 'blocked';
            return _blocked( $result->{time_remaining} );
        }
    }

    my $state = DW::RateLimit->defer_protocol_request($ip);
    my $res   = $self->app->($env);

    # A request that failed before authenticating (or never reached the
    # protocol) is charged as anonymous now. It has already run, but it did
    # little work, and the caller still sees the 429.
    my $retry_after = DW::RateLimit->charge_protocol_request( state => $state );

    $env->{'dw.stats.ratelimit'} = $retry_after ? 'blocked' : 'allowed';
    return $retry_after ? _blocked($retry_after) : $res;
}

sub _blocked {
    my ($retry_after) = @_;
    return [
        429,
        [
            'Content-Type' => 'text/html',
            'Retry-After'  => $retry_after,
        ],
        [ DW::RateLimit->blocked_body($retry_after) ]
    ];
}

1;
