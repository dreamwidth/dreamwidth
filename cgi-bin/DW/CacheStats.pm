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
use DW::RequestCache;

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

    # The process-global caches registered below, plus the request-scoped set
    # pulled live from DW::RequestCache -- the same registry LJ::start_request
    # clears, so the measured set and the cleared set stay in lockstep.
    my @entries = map { { name => $_, getref => $CACHES{$_} } } keys %CACHES;
    push @entries, DW::RequestCache->registered;

    foreach my $entry (@entries) {
        my $ref = eval { $entry->{getref}->() };
        next unless ref $ref;

        DW::Stats::timing( 'dw.cache.bytes', total_size($ref), ["cache:$entry->{name}"] );
    }

    return 1;
}

# Built-in registrations for the persistent process-global caches (the unbounded
# memory-growth suspects). These are always reachable as symbols, so we reference
# them directly rather than touching the owning code. They live for the life of
# the process. The request-scoped caches are not registered here -- they come
# from DW::RequestCache at report() time (see above), so the measured set can't
# drift from the set LJ::start_request actually clears.
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

1;
