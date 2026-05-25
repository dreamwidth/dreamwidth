#!/usr/bin/perl
#
# Plack::Middleware::DW::AccessLog tests
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use Test::More tests => 5;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use Plack::Middleware::DW::AccessLog;

my $mw = Plack::Middleware::DW::AccessLog->new;

# Full hints from downstream middleware produce all four tags, in order.
is_deeply(
    $mw->_request_tags(
        {
            'dw.stats.auth'      => 'user',
            'dw.stats.ratelimit' => 'blocked',
            REQUEST_METHOD       => 'POST',
        },
        429
    ),
    [ 'auth:user', 'ratelimit:blocked', 'status:429', 'method:POST' ],
    'full hints produce all four tags'
);

# Missing hints (request never reached Auth/RateLimit) fall back to defaults.
is_deeply(
    $mw->_request_tags( {}, 200 ),
    [ 'auth:anon', 'ratelimit:skipped', 'status:200', 'method:GET' ],
    'missing hints default to anon/skipped/GET'
);

# Partial hints: method present but no auth/ratelimit hints (defaults still apply).
is_deeply(
    $mw->_request_tags( { REQUEST_METHOD => 'DELETE' }, 204 ),
    [ 'auth:anon', 'ratelimit:skipped', 'status:204', 'method:DELETE' ],
    'partial env: method present but auth/ratelimit hints absent'
);

# Integration: call() through to _log emits a counter + a timing to the configured
# DogStatsD socket, both carrying the request tags.
use DW::Stats;
use IO::Socket::INET;
use IO::Select;

my $server = IO::Socket::INET->new(
    Proto     => 'udp',
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
) or die "cannot create udp listener: $!";
my $select = IO::Select->new($server);

sub recv_packet {
    return undef unless $select->can_read(2);
    my $data = '';
    $server->recv( $data, 1024 );
    return $data;
}

DW::Stats::setup( '127.0.0.1', $server->sockport );

my $emit_mw = Plack::Middleware::DW::AccessLog->new;
$emit_mw->app( sub { [ 200, [ 'Content-Type' => 'text/plain' ], ['ok'] ] } );

open my $errfh, '>', \my $errbuf or die "cannot open in-memory errors handle: $!";
my %env = (
    REQUEST_METHOD       => 'GET',
    PATH_INFO            => '/',
    'dw.stats.auth'      => 'anon',
    'dw.stats.ratelimit' => 'allowed',
    'psgi.errors'        => $errfh,
);
$emit_mw->call( \%env );

# Two packets, order preserved on a single loopback socket: counter then timing.
is(
    recv_packet(),
    'dw.request:1|c|#auth:anon,ratelimit:allowed,status:200,method:GET',
    'call() emits the dw.request counter with tags'
);
like(
    recv_packet(),
    qr{^dw\.request\.duration_ms:[0-9.]+\|ms\|#auth:anon,ratelimit:allowed,status:200,method:GET$},
    'call() emits the dw.request.duration_ms timing with tags'
);
