#!/usr/bin/perl
#
# DW::Stats
#
# This module is used for sending statistics off to a statistics interface,
# which might publish statistics somewhere. This is mostly used for business
# metrics of events.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Stats;

use strict;
use IO::Socket::INET;
use Time::HiRes qw/ tv_interval /;

my $sock;

# Usage: DW::Stats::setup( host, port )
#
# Enables the stats system to start posting statistics to the given host and
# port. This must be called in order for the other methods in this module to
# actually do anything.
sub setup {
    die "Not enough arguments to setup\n"
        unless scalar(@_) == 2;

    $sock = IO::Socket::INET->new(
        Proto    => 'udp',
        PeerAddr => $_[0],
        PeerPort => $_[1],
    );
}

# Usage: DW::Stats::increment( 'my.metric', $incrby, $tags, $sample_rate )
#
# Metric must be a string. $incrby must be a number or undef. $tags must be an
# arrayref or undef. $sample_rate must be undef or a number 0..1.
sub increment {
    return unless $sock;

    my ( $metric, $incrby, $tags, $sample_rate ) = @_;
    $incrby //= 1;

    if ( !defined $sample_rate || rand() < $sample_rate ) {
        $sample_rate = defined $sample_rate ? "|\@$sample_rate" : "";
        $tags = ref $tags eq 'ARRAY' ? '|#' . join( ',', @$tags ) : '';
        $sock->send("$metric:$incrby|c$sample_rate$tags");
    }
}

1;
