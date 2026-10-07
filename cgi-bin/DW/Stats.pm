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

# Usage: DW::Stats::enabled()
#
# Returns true if a stats sink has been configured via setup(). Useful for
# guarding expensive measurement work that would otherwise be discarded.
sub enabled {
    return defined $sock ? 1 : 0;
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

# Usage: DW::Stats::gauge( 'my.metric', $gauge_level, $tags )
#
# Metric must be a string. $gauge_level must be a number. $tags must be an
# arrayref or undef.
sub gauge {
    return unless $sock;

    my ( $metric, $gauge, $tags ) = @_;
    return unless defined $gauge;

    $tags = ref $tags eq 'ARRAY' ? '|#' . join( ',', @$tags ) : '';
    $sock->send("$metric:$gauge|g$tags");
}

# Usage: DW::Stats::timing( 'my.metric', $value_ms, $tags, $sample_rate )
#
# Metric must be a string. $value_ms must be a number (milliseconds). $tags must be
# an arrayref or undef. $sample_rate must be undef or a number 0..1.
sub timing {
    return unless $sock;

    my ( $metric, $value, $tags, $sample_rate ) = @_;
    return unless defined $value;

    if ( !defined $sample_rate || rand() < $sample_rate ) {
        $sample_rate = defined $sample_rate ? "|\@$sample_rate" : "";
        $tags = ref $tags eq 'ARRAY' ? '|#' . join( ',', @$tags ) : '';
        $sock->send("$metric:$value|ms$sample_rate$tags");
    }
}

my $page_size;

sub _page_size {
    return $page_size if defined $page_size;
    $page_size = eval { require POSIX; POSIX::sysconf( POSIX::_SC_PAGESIZE() ) } || 4096;
    return $page_size;
}

# Resident set size of this process, in bytes, from /proc (Linux). Returns
# undef where /proc/self/statm is unavailable.
sub _rss_bytes {
    open my $fh, '<', '/proc/self/statm' or return undef;
    my $line = <$fh>;
    close $fh;
    return undef unless $line;

    my ( undef, $rss_pages ) = split /\s+/, $line;
    return undef unless defined $rss_pages;
    return $rss_pages * _page_size();
}

# Usage: DW::Stats::report_rss()
#
# Emits this process's resident set size (dw.process.rss_bytes) as a timing
# metric so the backend aggregates a histogram across workers. Sampled at
# $LJ::PROCESS_STATS_SAMPLE_RATE (0..1, defaults off); called once per request
# from LJ::start_request. A no-op unless a stats sink is configured.
sub report_rss {
    my $rate = $LJ::PROCESS_STATS_SAMPLE_RATE;
    return unless $rate && $sock;
    return unless rand() < $rate;

    my $rss = _rss_bytes();
    timing( 'dw.process.rss_bytes', $rss ) if defined $rss;
    return 1;
}

1;
