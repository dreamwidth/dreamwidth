#!/usr/bin/perl
#
# DW::RequestCache
#
# The single home for request-scoped state: anything that should live only for
# the duration of one web request or one background job, and must be wiped
# before the next one begins. There are two ways in, and clear() empties both:
#
#   1. The KV store (the happy path). Memoize keyed lookups with get/set/memoize/
#      remove under a namespace. Nothing to register; it is always cleared.
#
#   2. Registration. For request-scoped state that keeps direct package-var
#      access (scratch hashes, accumulators, scalars, per-class singletons),
#      register the variable (register_var) or a reset action (register_reset)
#      once, and clear() takes care of it.
#
# The whole point is the guarantee: clear() wipes everything routed through this
# module, so a cache added here CANNOT leak across requests. It is driven from
# LJ::start_request (web requests) and DW::TaskQueue (background jobs). Adding a
# new request cache no longer means remembering to edit a clear-list somewhere.
#
# DW::CacheStats samples the same registry it clears (see ->registered), so the
# measured set and the cleared set can never drift apart.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::RequestCache;

use strict;
use warnings;

use Carp qw( croak );

# The KV store: namespace => { key => value }. One hash, so one assignment
# wipes every memoized value.
our %STORE;

# Registered non-KV state. name => { getref => sub {\%h}|undef, clear => sub {} }.
# getref (when present) hands DW::CacheStats a reference to sample; clear is the
# action run to empty the state.
my %REGISTRY;

# ---- KV store API -----------------------------------------------------------

# get( $ns, $key ) -> value or undef. Does not autovivify the namespace.
sub get {
    my ( $class, $ns, $key ) = @_;
    return undef unless exists $STORE{$ns};
    return $STORE{$ns}->{$key};
}

# has( $ns, $key ) -> bool. For callers that must tell "cached as undef/false"
# apart from "not cached".
sub has {
    my ( $class, $ns, $key ) = @_;
    return exists $STORE{$ns} && exists $STORE{$ns}->{$key};
}

# set( $ns, $key, $value ) -> value.
sub set {
    my ( $class, $ns, $key, $value ) = @_;
    return $STORE{$ns}->{$key} = $value;
}

# memoize( $ns, $key, $coderef ) -> value. Computes once and caches, including
# a false/undef result (unlike a truthy get-or-compute).
sub memoize {
    my ( $class, $ns, $key, $code ) = @_;
    return $STORE{$ns}->{$key} if exists $STORE{$ns} && exists $STORE{$ns}->{$key};
    return $STORE{$ns}->{$key} = $code->();
}

# remove( $ns, $key ). Invalidate a single entry.
sub remove {
    my ( $class, $ns, $key ) = @_;
    delete $STORE{$ns}->{$key} if exists $STORE{$ns};
    return 1;
}

# clear_ns( $ns ). Drop a whole namespace.
sub clear_ns {
    my ( $class, $ns ) = @_;
    delete $STORE{$ns};
    return 1;
}

# ---- Registration API -------------------------------------------------------

# register_var( $name, \%hash | \@array ). Register a request-scoped variable
# that keeps direct access at its call sites; clear() empties it in place.
sub register_var {
    my ( $class, $name, $ref ) = @_;

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

    $REGISTRY{$name} = { getref => sub { $ref }, clear => $clear };
    return 1;
}

# register_reset( $name, $coderef ). Register an arbitrary reset action for
# state that isn't a plain hash/array (scalars, per-class singleton registries).
# There is nothing to sample, so it does not appear in ->registered.
sub register_reset {
    my ( $class, $name, $code ) = @_;
    croak "register_reset($name) needs a CODE reference"
        unless ref $code eq 'CODE';

    $REGISTRY{$name} = { getref => undef, clear => $code };
    return 1;
}

# ---- The guarantee ----------------------------------------------------------

# clear(). Wipe the KV store and run every registration. Called once per web
# request (LJ::start_request) and once per background job (DW::TaskQueue).
sub clear {
    %STORE = ();
    $_->{clear}->() for values %REGISTRY;
    return 1;
}

# registered(). For DW::CacheStats: the samplable entries (the KV store plus
# every register_var), as ( { name => ..., getref => sub {...} }, ... ).
# register_reset entries are omitted (no structure to measure).
sub registered {
    my @out = (
        {
            name   => 'request_cache_store',
            getref => sub { \%STORE }
        }
    );
    foreach my $name ( sort keys %REGISTRY ) {
        my $getref = $REGISTRY{$name}->{getref} or next;
        push @out, { name => $name, getref => $getref };
    }
    return @out;
}

# ---- Central registrations --------------------------------------------------
#
# Request-scoped package globals that keep direct access. They are all reachable
# as symbols, so we register them here rather than touching each owning module
# (mirroring DW::CacheStats). Keyed memoization caches do NOT belong here — they
# live in the KV store above.

DW::RequestCache->register_var( 'req_global',         \%LJ::REQ_GLOBAL );
DW::RequestCache->register_var( 'ml_used_strings',    \%LJ::_ML_USED_STRINGS );
DW::RequestCache->register_var( 'paid_status',        \%LJ::PAID_STATUS );
DW::RequestCache->register_var( 'req_head_has',       \%LJ::REQ_HEAD_HAS );
DW::RequestCache->register_var( 'needed_res',         \%LJ::NEEDED_RES );
DW::RequestCache->register_var( 'needed_res_order',   \@LJ::NEEDED_RES );
DW::RequestCache->register_var( 'cache_userpic',      \%LJ::CACHE_USERPIC );
DW::RequestCache->register_var( 'cache_userpic_info', \%LJ::CACHE_USERPIC_INFO );
DW::RequestCache->register_var( 'cache_s2theme',      \%LJ::CACHE_S2THEME );

# Per-request scalars back to their unset state.
DW::RequestCache->register_reset(
    'req_scalars',
    sub {
        $LJ::ACTIVE_JOURNAL          = undef;
        $LJ::ACTIVE_RES_GROUP        = undef;
        $LJ::CACHE_REMOTE_BOUNCE_URL = undef;
    }
);

# Cached remote user.
DW::RequestCache->register_reset( 'remote', sub { LJ::unset_remote() } );

# Per-class object singletons.
DW::RequestCache->register_reset(
    'singletons',
    sub {
        LJ::Userpic->reset_singletons;
        LJ::Comment->reset_singletons;
        LJ::Entry->reset_singletons;
        LJ::Message->reset_singletons;
    }
);

1;
