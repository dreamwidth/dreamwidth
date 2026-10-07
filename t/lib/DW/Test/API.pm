#!/usr/bin/perl
#
# DW::Test::API
#
# Helpers for end-to-end tests of the REST API: requests go through the full
# Plack application with a real API key, so routing, key auth, spec validation,
# rate limiting, controllers, and backends are all exercised.
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

package DW::Test::API;

use strict;
use warnings;

use Exporter 'import';
use HTTP::Request;
use JSON;
use Plack::Test;
use URI;

use DW::API::Key;
use LJ::Entry;
use LJ::Test qw(temp_user);

our @EXPORT = qw(api_user api_request fresh_entry entry_state);

my $test;

sub _test {
    return $test if $test;

    my $app = do "$ENV{LJHOME}/app.psgi";
    die $@ unless ref $app eq 'CODE';
    return $test = Plack::Test->create($app);
}

# Returns ( $u, $keyhash ) for a new temporary user with an API key.
sub api_user {
    my $u = temp_user();
    return ( $u, DW::API::Key->new_for_user($u)->hash );
}

# Usage: my ( $res, $body ) = api_request( METHOD => '/path', %opts );
#
# The path is relative to /api/v1. Options:
#   key          - API key, sent as "Authorization: Bearer <key>"
#   auth         - raw Authorization header value (overrides key)
#   json         - request body; references are JSON-encoded, strings are sent as-is
#   content_type - defaults to application/json when a body is given
#   query        - hashref of query parameters
#
# $body is the decoded JSON response, or undef if the response isn't JSON.
sub api_request {
    my ( $method, $path, %opts ) = @_;

    my $uri = URI->new("http://localhost/api/v1$path");
    $uri->query_form( $opts{query} ) if $opts{query};

    my @headers;
    if ( defined $opts{auth} ) {
        push @headers, Authorization => $opts{auth};
    }
    elsif ( defined $opts{key} ) {
        push @headers, Authorization => "Bearer $opts{key}";
    }

    my $content;
    if ( exists $opts{json} ) {
        $content = ref $opts{json} ? encode_json( $opts{json} ) : $opts{json};
        push @headers, 'Content-Type' => $opts{content_type} // 'application/json';
    }
    elsif ( defined $opts{content_type} ) {
        push @headers, 'Content-Type' => $opts{content_type};
    }

    my $res  = _test()->request( HTTP::Request->new( $method, $uri, \@headers, $content ) );
    my $body = eval { JSON->new->allow_nonref->decode( $res->content ) };
    return ( $res, $body );
}

# Loads an entry by ditemid, bypassing the per-request entry cache so that
# changes made by an API request are visible.
sub fresh_entry {
    my ( $u, $ditemid ) = @_;

    LJ::Entry->reset_singletons;
    LJ::start_request();
    return LJ::Entry->new( $u, ditemid => $ditemid );
}

# Returns the entry settings an edit could change, for before/after comparisons.
sub entry_state {
    my ($entry) = @_;

    return {
        subject   => $entry->subject_raw,
        event     => $entry->event_raw,
        security  => $entry->security,
        allowmask => $entry->allowmask,
        eventtime => $entry->eventtime_mysql,
        tags      => join( ', ', sort $entry->tags ),
        slug      => $entry->slug,
        map { $_ => $entry->prop($_) // '' }
            qw( opt_backdated opt_nocomments opt_noemail opt_screening
            adult_content adult_content_reason current_music current_location ),
    };
}

1;
