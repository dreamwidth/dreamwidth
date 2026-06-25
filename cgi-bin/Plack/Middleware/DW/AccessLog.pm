#!/usr/bin/perl
#
# Plack::Middleware::DW::AccessLog
#
# JSON access log middleware for Grafana Loki dashboards.  Emits one JSON
# object per line to psgi.errors (stderr) or to a file when log_file is set.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package Plack::Middleware::DW::AccessLog;

use strict;
use v5.10;

use parent qw/ Plack::Middleware /;
use Plack::Util::Accessor qw( log_file );

use LJ::JSON;
use POSIX qw( strftime );
use Time::HiRes qw( gettimeofday tv_interval );

use DW::Stats;

sub prepare_app {
    my $self = shift;

    if ( my $path = $self->log_file ) {
        open my $fh, '>>', $path or die "Cannot open access log $path: $!";
        $fh->autoflush(1);
        $self->{_log_fh} = $fh;
    }
}

sub call {
    my ( $self, $env ) = @_;

    my $t0 = [gettimeofday];

    my $res = $self->app->($env);

    # Handle both standard arrayref responses and streaming/delayed
    # (code ref) responses per the PSGI spec.
    if ( ref $res eq 'CODE' ) {
        return $self->response_cb(
            $res,
            sub {
                my $res = shift;
                $self->_log( $env, $t0, $res );
            }
        );
    }

    $self->_log( $env, $t0, $res );
    return $res;
}

sub _log {
    my ( $self, $env, $t0, $res ) = @_;

    my $duration    = tv_interval($t0) * 1000;            # milliseconds
    my $duration_ms = sprintf( '%.1f', $duration ) + 0;

    # Per-request metrics for Grafana (volume counter + latency timing). No-op when
    # %LJ::STATS is unset (dev container, tests), so no behavior change locally.
    # Note: for streaming/code-ref responses _log runs at time-to-first-byte, so
    # the latency captured reflects that rather than full body-stream time.
    #
    # We send the value in milliseconds (statsd "ms" timer type), but the Prometheus
    # statsd_exporter converts "ms" timers to base-unit seconds -- so the metric is
    # named dw.request.duration_seconds to match the unit it actually stores.
    my $tags = $self->_request_tags( $env, $res->[0] );
    DW::Stats::increment( 'dw.request', 1, $tags );
    DW::Stats::timing( 'dw.request.duration_seconds', $duration_ms, $tags );

    # Content-Length from the response headers (may be undef for streaming)
    my $bytes;
    my $headers = $res->[1];
    for ( my $i = 0 ; $i < @$headers ; $i += 2 ) {
        if ( lc( $headers->[$i] ) eq 'content-length' ) {
            $bytes = $headers->[ $i + 1 ];
            last;
        }
    }

    my ( $epoch, $usec ) = gettimeofday;
    my $ts = strftime( '%Y-%m-%dT%H:%M:%S', gmtime($epoch) ) . sprintf( '.%03dZ', $usec / 1000 );

    my %entry = (
        ts          => $ts,
        method      => $env->{REQUEST_METHOD},
        path        => $env->{PATH_INFO} || '/',
        status      => $res->[0],
        duration_ms => $duration_ms,
    );

    # Optional fields — omit rather than logging placeholder values
    $entry{query}      = $env->{QUERY_STRING}    if length( $env->{QUERY_STRING} // '' );
    $entry{bytes}      = $bytes                  if defined $bytes;
    $entry{host}       = $env->{HTTP_HOST}       if $env->{HTTP_HOST};
    $entry{remote_ip}  = $env->{REMOTE_ADDR}     if $env->{REMOTE_ADDR};
    $entry{user_agent} = $env->{HTTP_USER_AGENT} if $env->{HTTP_USER_AGENT};

    my $line = to_json( \%entry ) . "\n";
    if ( $self->{_log_fh} ) {
        $self->{_log_fh}->print($line);
    }
    else {
        $env->{'psgi.errors'}->print($line);
    }
}

# Build the DogStatsD tag arrayref for a request from the PSGI env and final HTTP
# status. Reads the auth / rate-limit hints stashed in the env by downstream
# middleware (DW::RateLimit), defaulting for requests that never reached them
# (static files, redirects, early exits): auth -> anon, ratelimit -> skipped.
sub _request_tags {
    my ( $self, $env, $status ) = @_;
    return [
        'auth:' .      ( $env->{'dw.stats.auth'}      // 'anon' ),
        'ratelimit:' . ( $env->{'dw.stats.ratelimit'} // 'skipped' ),
        'status:' . $status,
        'method:' . ( $env->{REQUEST_METHOD} // 'GET' ),
    ];
}

1;
