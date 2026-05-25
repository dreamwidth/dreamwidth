#!/usr/bin/perl
#
# DW::Stats tests
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

use Test::More tests => 4;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Stats;
use IO::Socket::INET;
use IO::Select;

# Loopback UDP listener that DW::Stats will send to.
my $server = IO::Socket::INET->new(
    Proto     => 'udp',
    LocalAddr => '127.0.0.1',
    LocalPort => 0,
) or die "cannot create udp listener: $!";
my $select = IO::Select->new($server);

# Receive one packet, or undef if nothing arrives within 2s (so a missing emit
# fails the test instead of hanging it).
sub recv_packet {
    return undef unless $select->can_read(2);
    my $data = '';
    $server->recv( $data, 1024 );
    return $data;
}

DW::Stats::setup( '127.0.0.1', $server->sockport );

# Timing with tags.
DW::Stats::timing( 'dw.request.duration_seconds', 12.5, [ 'auth:anon', 'status:200' ] );
is(
    recv_packet(),
    'dw.request.duration_seconds:12.5|ms|#auth:anon,status:200',
    'timing emits |ms type with tags'
);

# Timing without tags.
DW::Stats::timing( 'dw.timer', 7 );
is( recv_packet(), 'dw.timer:7|ms', 'timing emits |ms type without tags' );

# Sample rate is serialized as |@rate before the tags.
DW::Stats::timing( 'dw.sampled', 3, ['x:y'], 1 );
is( recv_packet(), 'dw.sampled:3|ms|@1|#x:y', 'timing serializes sample rate' );

# Undefined value emits nothing; a following emit confirms the undef one was skipped.
DW::Stats::timing( 'dw.skipped', undef );
DW::Stats::timing( 'dw.after',   1 );
is( recv_packet(), 'dw.after:1|ms', 'timing with undef value emits nothing' );
