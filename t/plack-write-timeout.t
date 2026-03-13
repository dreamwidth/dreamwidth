#!/usr/bin/perl
# t/plack-write-timeout.t
#
# Test the DW::WriteTimeout Plack middleware, which sets SO_SNDTIMEO on the
# client socket to prevent workers from blocking indefinitely when the
# downstream peer (ALB) disconnects mid-response.
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

use strict;
use warnings;
use v5.10;

use Test::More tests => 12;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

use IO::Socket::INET;
use Socket qw/ SOL_SOCKET SO_SNDTIMEO /;

# Test 1: Module loads
use_ok('Plack::Middleware::DW::WriteTimeout');

# Test 2-3: Instantiation with default and custom timeout
my $mw_default = Plack::Middleware::DW::WriteTimeout->new( app => sub { } );
ok( defined $mw_default, 'Middleware instantiates with defaults' );

my $mw_custom = Plack::Middleware::DW::WriteTimeout->new( app => sub { }, timeout => 10 );
is( $mw_custom->timeout, 10, 'Custom timeout value is stored' );

# Test 4-7: Middleware sets SO_SNDTIMEO on a real socket
#
# We create a real TCP listener and connect to it, then pass the connected
# socket as psgix.io in a PSGI env. After the middleware runs, we verify
# that SO_SNDTIMEO was set on the socket.

my $listener = IO::Socket::INET->new(
    Listen    => 1,
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
    Proto     => 'tcp',
    ReuseAddr => 1,
) or die "Cannot create listener: $!";

my $port = $listener->sockport;

my $client = IO::Socket::INET->new(
    PeerAddr => '127.0.0.1',
    PeerPort => $port,
    Proto    => 'tcp',
) or die "Cannot connect: $!";

my $server_sock = $listener->accept() or die "Cannot accept: $!";

# Verify timeout is initially 0 (no timeout)
my $initial = getsockopt( $server_sock, SOL_SOCKET, SO_SNDTIMEO );
my ( $initial_secs, $initial_usecs ) = unpack( 'l!l!', $initial );
is( $initial_secs, 0, 'SO_SNDTIMEO initially 0 (no timeout)' );

# Build a PSGI env with psgix.io pointing to our socket
my $app_called = 0;
my $inner_app  = sub {
    $app_called = 1;
    return [ 200, [ 'Content-Type' => 'text/plain' ], ['OK'] ];
};

my $mw = Plack::Middleware::DW::WriteTimeout->new( app => $inner_app, timeout => 5 );

my $env = {
    'REQUEST_METHOD'  => 'GET',
    'PATH_INFO'       => '/',
    'QUERY_STRING'    => '',
    'SERVER_NAME'     => 'localhost',
    'SERVER_PORT'     => 8080,
    'HTTP_HOST'       => 'localhost',
    'SCRIPT_NAME'     => '',
    'psgix.io'        => $server_sock,
    'psgi.version'    => [ 1, 1 ],
    'psgi.url_scheme' => 'http',
    'psgi.input'      => \*STDIN,
    'psgi.errors'     => \*STDERR,
};

my $res = $mw->call($env);
ok( $app_called, 'Inner app was called' );

# Verify SO_SNDTIMEO was set to 5 seconds
my $packed = getsockopt( $server_sock, SOL_SOCKET, SO_SNDTIMEO );
my ( $secs, $usecs ) = unpack( 'l!l!', $packed );
is( $secs, 5, 'SO_SNDTIMEO set to 5 seconds' );

# Verify the response passed through unchanged
is_deeply( $res, [ 200, [ 'Content-Type' => 'text/plain' ], ['OK'] ],
    'Response passed through unchanged' );

# Clean up
close $server_sock;
close $client;
close $listener;

# Test 8-9: Works without psgix.io (shouldn't crash)
my $no_socket_called = 0;
my $mw_no_sock = Plack::Middleware::DW::WriteTimeout->new(
    app     => sub { $no_socket_called = 1; return [ 200, [], ['OK'] ]; },
    timeout => 5,
);

my $env_no_sock = {
    'REQUEST_METHOD'  => 'GET',
    'PATH_INFO'       => '/',
    'QUERY_STRING'    => '',
    'SERVER_NAME'     => 'localhost',
    'SERVER_PORT'     => 8080,
    'HTTP_HOST'       => 'localhost',
    'SCRIPT_NAME'     => '',
    'psgi.version'    => [ 1, 1 ],
    'psgi.url_scheme' => 'http',
    'psgi.input'      => \*STDIN,
    'psgi.errors'     => \*STDERR,
};

my $res2;
eval { $res2 = $mw_no_sock->call($env_no_sock); };
ok( !$@, 'No crash when psgix.io is absent' );
ok( $no_socket_called, 'Inner app still called without psgix.io' );

# Tests 10-11: Functional tests — contrast WITH and WITHOUT SO_SNDTIMEO
#
# Both tests create a TCP socket pair where the reader stops reading,
# then write large chunks until the send buffer fills and write() blocks.
#
# WITHOUT the timeout: write() blocks indefinitely — we use alarm() to
# prove it's still stuck after 5 seconds, demonstrating the production bug.
#
# WITH the timeout: write() fails quickly, freeing the worker.
SKIP: {
    skip "Functional write timeout tests (set TEST_WRITE_TIMEOUT=1)", 2
        unless $ENV{TEST_WRITE_TIMEOUT};

    # Helper: create a connected socket pair and shut down the reader
    my $make_stalled_pair = sub {
        my $listener = IO::Socket::INET->new(
            Listen    => 1,
            LocalAddr => '127.0.0.1',
            LocalPort => 0,
            Proto     => 'tcp',
            ReuseAddr => 1,
        ) or die "Cannot create listener: $!";

        my $writer = IO::Socket::INET->new(
            PeerAddr => '127.0.0.1',
            PeerPort => $listener->sockport,
            Proto    => 'tcp',
        ) or die "Cannot connect: $!";

        my $reader = $listener->accept() or die "Cannot accept: $!";
        close $listener;

        # Stop reading — writes will fill the buffer and block
        shutdown( $reader, 0 );

        return ( $writer, $reader );
    };

    # Test 10: WITHOUT SO_SNDTIMEO — write blocks, alarm rescues us
    {
        my ( $writer, $reader ) = $make_stalled_pair->();
        my $chunk       = 'X' x 65536;
        my $was_alarmed = 0;

        local $SIG{ALRM} = sub { $was_alarmed = 1; die "alarm\n" };
        alarm(5);

        eval {
            for ( 1 .. 100000 ) {
                syswrite( $writer, $chunk ) or last;
            }
        };
        alarm(0);

        ok( $was_alarmed,
            'WITHOUT SO_SNDTIMEO: write blocked until alarm after 5s (reproduces the bug)' );

        close $writer;
        close $reader;
    }

    # Test 11: WITH SO_SNDTIMEO — write fails on its own, no alarm needed
    {
        my ( $writer, $reader ) = $make_stalled_pair->();

        # Set a 1-second send timeout
        my $tv = pack( 'l!l!', 1, 0 );
        setsockopt( $writer, SOL_SOCKET, SO_SNDTIMEO, $tv )
            or die "setsockopt: $!";

        my $chunk     = 'X' x 65536;
        my $timed_out = 0;
        my $start     = time();
        for ( 1 .. 100000 ) {
            my $written = syswrite( $writer, $chunk );
            unless ( defined $written ) {
                $timed_out = 1;
                last;
            }
        }
        my $elapsed = time() - $start;

        ok( $timed_out && $elapsed < 10,
            "WITH SO_SNDTIMEO: write failed in ${elapsed}s (expected ~1-3s)" );

        close $writer;
        close $reader;
    }
}

# Test 12: Verify the middleware integrates correctly — run the full
# middleware against a socket and confirm SO_SNDTIMEO is what we set
{
    my $listener = IO::Socket::INET->new(
        Listen    => 1,
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Proto     => 'tcp',
        ReuseAddr => 1,
    ) or die "Cannot create listener: $!";

    my $client = IO::Socket::INET->new(
        PeerAddr => '127.0.0.1',
        PeerPort => $listener->sockport,
        Proto    => 'tcp',
    ) or die "Cannot connect: $!";

    my $sock = $listener->accept() or die "Cannot accept: $!";
    close $listener;

    my $mw_int = Plack::Middleware::DW::WriteTimeout->new(
        app     => sub { return [ 200, [], ['OK'] ] },
        timeout => 7,
    );

    $mw_int->call( {
        'REQUEST_METHOD'  => 'GET',
        'PATH_INFO'       => '/',
        'QUERY_STRING'    => '',
        'SERVER_NAME'     => 'localhost',
        'SERVER_PORT'     => 8080,
        'HTTP_HOST'       => 'localhost',
        'SCRIPT_NAME'     => '',
        'psgix.io'        => $sock,
        'psgi.version'    => [ 1, 1 ],
        'psgi.url_scheme' => 'http',
        'psgi.input'      => \*STDIN,
        'psgi.errors'     => \*STDERR,
    } );

    my $packed = getsockopt( $sock, SOL_SOCKET, SO_SNDTIMEO );
    my ( $s, $us ) = unpack( 'l!l!', $packed );
    is( $s, 7, 'Integration: middleware set SO_SNDTIMEO to configured value' );

    close $sock;
    close $client;
}
