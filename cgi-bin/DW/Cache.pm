#!/usr/bin/perl
#
# DW::Cache
#
# The single home for in-process caching, organized by lifetime. Pick a scope
# by answering: how long may this be stale, and who has to see it?
#
#   DW::Cache->request  -- correct only for the current web request or
#       background job. Cleared by LJ::start_request (web front door and
#       DW::TaskQueue both call it), so nothing can leak between visitors
#       or between jobs on a persistent worker.
#
#   DW::Cache->process  -- global reference data where stale-until-reload is
#       acceptable (prop definitions, moods, codes, translation strings).
#       Cleared by LJ::handle_caches on config reload ($LJ::CLEAR_CACHES).
#
# For state shared across processes or hosts, use LJ::MemCache instead.
#
# Each scope offers two ways in, and one clear() empties both:
#
#   1. The KV store (the happy path). Memoize keyed lookups with get/set/
#      memoize/remove under a namespace. Nothing to register; it is always
#      cleared with the scope.
#
#   2. Registration. For state that keeps direct package-var access (scratch
#      hashes, accumulators, scalars), register the variable (register_var)
#      or a reset action (register_reset) once, and clear() takes care of it.
#
# The point is the guarantee: clear() wipes everything routed through a scope,
# so a cache added here CANNOT leak past its lifetime. Adding a cache no longer
# means remembering to edit a clear-list somewhere else.
#
# Cache byte sizes are emitted by report_sizes() from the same registries that
# clear() wipes, so the measured set and the cleared set can never drift apart.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Cache;

use strict;
use warnings;

use Devel::Size ();

use DW::Stats;

my ( $request, $process );

sub request { return $request ||= DW::Cache::Scope->_new('request') }
sub process { return $process ||= DW::Cache::Scope->_new('process') }

# Usage: DW::Cache->report_sizes
#
# Sampled at $LJ::CACHE_STATS_SAMPLE_RATE (0..1). When it fires, emits the byte
# size of every KV namespace and registered variable in both scopes as timing
# metrics (dw.cache.bytes, tagged cache:<name> and scope:<scope>), so the stats
# backend aggregates them into histograms across workers. Measurement deep-walks
# each cache with Devel::Size, so it is expensive; a no-op unless a stats sink
# is configured and the sample rate is positive. Call just before the request
# scope is cleared, so each sample reflects a request's peak.
sub report_sizes {
    my $rate = $LJ::CACHE_STATS_SAMPLE_RATE;
    return unless $rate && DW::Stats::enabled();
    return unless rand() < $rate;

    foreach my $scope ( request(), process() ) {
        foreach my $entry ( $scope->_measurable ) {
            my $ref = eval { $entry->{getref}->() };
            next unless ref $ref;

            DW::Stats::timing(
                'dw.cache.bytes',
                Devel::Size::total_size($ref),
                [ "cache:$entry->{name}", "scope:" . $scope->name ]
            );
        }
    }

    return 1;
}

################################################################################

package DW::Cache::Scope;

use strict;
use warnings;

use Carp qw( croak );

sub _new {
    my ( $class, $name ) = @_;
    return bless {
        name     => $name,
        store    => {},      # KV: namespace => { key => value }
        registry => {},      # name => { getref => sub|undef, clear => sub }
    }, $class;
}

sub name { return $_[0]->{name} }

# ---- KV store API -----------------------------------------------------------

# get( $ns, $key ) -> value or undef. Does not autovivify the namespace.
sub get {
    my ( $self, $ns, $key ) = @_;
    return undef unless exists $self->{store}{$ns};
    return $self->{store}{$ns}{$key};
}

# has( $ns, $key ) -> bool. For callers that must tell "cached as undef/false"
# apart from "not cached".
sub has {
    my ( $self, $ns, $key ) = @_;
    return exists $self->{store}{$ns} && exists $self->{store}{$ns}{$key};
}

# set( $ns, $key, $value ) -> value.
sub set {
    my ( $self, $ns, $key, $value ) = @_;
    return $self->{store}{$ns}{$key} = $value;
}

# memoize( $ns, $key, $coderef ) -> value. Computes once and caches, including
# a false/undef result (unlike a truthy get-or-compute).
sub memoize {
    my ( $self, $ns, $key, $code ) = @_;
    return $self->{store}{$ns}{$key}
        if exists $self->{store}{$ns} && exists $self->{store}{$ns}{$key};
    return $self->{store}{$ns}{$key} = $code->();
}

# remove( $ns, $key ). Invalidate a single entry.
sub remove {
    my ( $self, $ns, $key ) = @_;
    delete $self->{store}{$ns}{$key} if exists $self->{store}{$ns};
    return 1;
}

# clear_ns( $ns ). Drop a whole namespace.
sub clear_ns {
    my ( $self, $ns ) = @_;
    delete $self->{store}{$ns};
    return 1;
}

# ---- Registration API -------------------------------------------------------

# register_var( $name, \%hash | \@array ). Register a variable that keeps
# direct access at its call sites; clear() empties it in place, and
# report_sizes() measures it.
sub register_var {
    my ( $self, $name, $ref ) = @_;

    my $reftype = ref $ref;
    my $clear;
    if ( $reftype eq 'HASH' ) {
        $clear = sub { %$ref = () };
    }
    elsif ( $reftype eq 'ARRAY' ) {
        $clear = sub { @$ref = () };
    }
    else {
        croak "register_var($name) needs a HASH or ARRAY reference";
    }

    $self->{registry}{$name} = { getref => sub { $ref }, clear => $clear };
    return 1;
}

# register_reset( $name, $coderef ). Register an arbitrary reset action for
# state that isn't a plain hash/array (scalars, counters). There is nothing to
# sample, so it is not measured.
sub register_reset {
    my ( $self, $name, $code ) = @_;
    croak "register_reset($name) needs a CODE reference"
        unless ref $code eq 'CODE';

    $self->{registry}{$name} = { getref => undef, clear => $code };
    return 1;
}

# ---- The guarantee ----------------------------------------------------------

# clear(). Wipe the KV store and run every registration for this scope.
sub clear {
    my $self = $_[0];
    $self->{store} = {};
    $_->{clear}->() for values %{ $self->{registry} };
    return 1;
}

# The measurable entries: one per KV namespace, plus every register_var.
# register_reset entries are omitted (no structure to measure).
sub _measurable {
    my $self = $_[0];

    my @out;
    foreach my $ns ( sort keys %{ $self->{store} } ) {
        my $ref = $self->{store}{$ns};
        push @out, {
            name   => $ns,
            getref => sub { $ref }
        };
    }
    foreach my $name ( sort keys %{ $self->{registry} } ) {
        my $getref = $self->{registry}{$name}{getref} or next;
        push @out, { name => $name, getref => $getref };
    }
    return @out;
}

################################################################################

package DW::Cache;

# ---- Central registrations --------------------------------------------------
#
# Package globals that keep direct access at their call sites. They are all
# reachable as symbols, so we register them here rather than touching each
# owning module. Caches held in file-scoped lexicals self-register from their
# own module (e.g. LJ::Entry's singletons, LJ::UniqCookie, LJ::Lang). Keyed
# memoization caches do NOT belong here -- they live in the KV stores.

# Request scope: wiped between every web request / background job.
DW::Cache->request->register_var( 'req_global',         \%LJ::REQ_GLOBAL );
DW::Cache->request->register_var( 'ml_used_strings',    \%LJ::_ML_USED_STRINGS );
DW::Cache->request->register_var( 'paid_status',        \%LJ::PAID_STATUS );
DW::Cache->request->register_var( 'req_head_has',       \%LJ::REQ_HEAD_HAS );
DW::Cache->request->register_var( 'needed_res',         \%LJ::NEEDED_RES );
DW::Cache->request->register_var( 'needed_res_order',   \@LJ::NEEDED_RES );
DW::Cache->request->register_var( 'cache_userpic',      \%LJ::CACHE_USERPIC );
DW::Cache->request->register_var( 'cache_userpic_info', \%LJ::CACHE_USERPIC_INFO );
DW::Cache->request->register_var( 'cache_s2theme',      \%LJ::CACHE_S2THEME );

# Per-request scalars back to their unset state.
DW::Cache->request->register_reset(
    'req_scalars',
    sub {
        $LJ::ACTIVE_JOURNAL          = undef;
        $LJ::ACTIVE_RES_GROUP        = undef;
        $LJ::CACHE_REMOTE_BOUNCE_URL = undef;
    }
);

# Cached remote user.
DW::Cache->request->register_reset( 'remote', sub { LJ::unset_remote() } );

# Process scope: global reference data, wiped on config reload (HUP). These are
# the long-lived unbounded-growth suspects, so sizing them matters most.
DW::Cache->process->register_var( 'cache_userid',     \%LJ::CACHE_USERID );
DW::Cache->process->register_var( 'cache_username',   \%LJ::CACHE_USERNAME );
DW::Cache->process->register_var( 'cache_prop',       \%LJ::CACHE_PROP );
DW::Cache->process->register_var( 'cache_propid',     \%LJ::CACHE_PROPID );
DW::Cache->process->register_var( 'cache_style',      \%LJ::CACHE_STYLE );
DW::Cache->process->register_var( 'cache_moods',      \%LJ::CACHE_MOODS );
DW::Cache->process->register_var( 'cache_mood_theme', \%LJ::CACHE_MOOD_THEME );
DW::Cache->process->register_var( 'cache_codes',      \%LJ::CACHE_CODES );
DW::Cache->process->register_var( 'cache_userprop',   \%LJ::CACHE_USERPROP );
DW::Cache->process->register_var( 'cache_encodings',  \%LJ::CACHE_ENCODINGS );

# Mood-cache fill markers, reset alongside the mood hashes above.
DW::Cache->process->register_reset(
    'mood_counters',
    sub {
        $LJ::CACHED_MOODS    = 0;
        $LJ::CACHED_MOOD_MAX = 0;
    }
);

1;
