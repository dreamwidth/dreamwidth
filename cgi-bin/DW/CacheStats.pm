#!/usr/bin/perl
#
# DW::CacheStats
#
# Instruments the size (in bytes) of the various in-process caches the web
# process maintains, so we can track memory growth. Measurement is expensive
# (it deep-walks each cache with Devel::Size), so it is sampled: nothing is
# measured unless $LJ::CACHE_STATS_SAMPLE_RATE is set and a stats sink is
# configured. The cheap process RSS gauge is emitted on the same sampled path.
#
# Caches register themselves by name with a coderef that returns a reference to
# the underlying data structure. Package-global caches (the %LJ::CACHE_* family)
# are registered centrally below; caches held in file-scoped lexicals (e.g.
# %LJ::Lang::TXT_CACHE, the per-class singleton registries) self-register from
# their own module, after their declaration, so the closure can see them.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::CacheStats;

use strict;
use warnings;

use Devel::Size qw( total_size );

use DW::Stats;

# name -> coderef returning a reference to the cache structure to measure
our %CACHES;

# Usage: DW::CacheStats::register( 'some_cache', sub { \%Some::cache } )
#
# Registers a cache for size instrumentation. The coderef is called at report
# time and must return a reference (hashref/arrayref); anything else is skipped.
sub register {
    my ( $name, $getref ) = @_;
    $CACHES{$name} = $getref;
    return 1;
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

# Usage: DW::CacheStats::report()
#
# Sampled at $LJ::CACHE_STATS_SAMPLE_RATE (0..1). When it fires, emits the
# process RSS and the byte size of every registered cache as timing metrics, so
# the stats backend aggregates them into histograms across workers. A no-op
# unless a stats sink is configured and the sample rate is positive.
sub report {
    my $rate = $LJ::CACHE_STATS_SAMPLE_RATE;
    return unless $rate && DW::Stats::enabled();
    return unless rand() < $rate;

    my $rss = _rss_bytes();
    DW::Stats::timing( 'dw.process.rss_bytes', $rss ) if defined $rss;

    foreach my $name ( keys %CACHES ) {
        my $ref = eval { $CACHES{$name}->() };
        next unless ref $ref;

        DW::Stats::timing( 'dw.cache.bytes', total_size($ref), ["cache:$name"] );
    }

    return 1;
}

# Built-in registrations for the package-global caches. These are always
# reachable as symbols, so we can reference them directly here rather than
# touching the owning code. The per-request caches are measured at the top of
# LJ::start_request, just before they are cleared, so we capture each request's
# peak. The rest persist for the life of the process.
#
# Persistent process-global caches (the unbounded memory-growth suspects):
register( 'cache_userid',     sub { \%LJ::CACHE_USERID } );
register( 'cache_username',   sub { \%LJ::CACHE_USERNAME } );
register( 'cache_mood_theme', sub { \%LJ::CACHE_MOOD_THEME } );
register( 'cache_moods',      sub { \%LJ::CACHE_MOODS } );
register( 'cache_prop',       sub { \%LJ::CACHE_PROP } );
register( 'cache_propid',     sub { \%LJ::CACHE_PROPID } );
register( 'cache_codes',      sub { \%LJ::CACHE_CODES } );
register( 'cache_encodings',  sub { \%LJ::CACHE_ENCODINGS } );
register( 'cache_userprop',   sub { \%LJ::CACHE_USERPROP } );
register( 'cache_style',      sub { \%LJ::CACHE_STYLE } );

# Per-request caches (cleared every request; measured just before the clear):
register( 'req_cache_user_name',     sub { \%LJ::REQ_CACHE_USER_NAME } );
register( 'req_cache_user_id',       sub { \%LJ::REQ_CACHE_USER_ID } );
register( 'req_cache_rel',           sub { \%LJ::REQ_CACHE_REL } );
register( 'req_cache_usertags',      sub { \%LJ::REQ_CACHE_USERTAGS } );
register( 'cache_userpic',           sub { \%LJ::CACHE_USERPIC } );
register( 'cache_userpic_info',      sub { \%LJ::CACHE_USERPIC_INFO } );
register( 'cache_s2theme',           sub { \%LJ::CACHE_S2THEME } );
register( 'paid_status',             sub { \%LJ::PAID_STATUS } );
register( 'request_cache',           sub { \%LJ::REQUEST_CACHE } );
register( 'req_global',              sub { \%LJ::REQ_GLOBAL } );
register( 's2_req_cache_style_id',   sub { \%LJ::S2::REQ_CACHE_STYLE_ID } );
register( 's2_req_cache_layer_id',   sub { \%LJ::S2::REQ_CACHE_LAYER_ID } );
register( 's2_req_cache_layer_info', sub { \%LJ::S2::REQ_CACHE_LAYER_INFO } );

1;
