#!/usr/bin/perl
# t/plack-bml.t
#
# Router-only regression coverage for legacy .bml URLs, now that the BML
# rendering engine is gone (E3): unmatched URLs reach the router's ordinary
# 404, a bookmarked .bml link to a still-existing native page still routes
# there (DW::Routing discards a trailing '.bml' format), and the engine's
# old _config.bml special case is gone -- it is just another unmatched path.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use v5.10;

use Test::More;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# A bookmarked .bml link to a page that has since been migrated to a native
# route: DW::Routing::get_call_opts strips a trailing '.bml' format and
# routes it exactly like the extension-less URL.
test_psgi $app, sub {
    my $cb     = shift;
    my $native = $cb->( GET "/login" );
    my $bml    = $cb->( GET "/login.bml" );
    is( $native->code, 200,           '/login renders' );
    is( $bml->code,    $native->code, '/login.bml gets the same status as /login' );
    like( $bml->content, qr/<form/i, '/login.bml renders the real native page, not a 404' );
};

# The engine's old "_config.bml direct access is forbidden" special case is
# gone along with the engine; it is now just another unmatched path.
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/_config.bml" );
    is( $res->code, 404, '/_config.bml is an ordinary 404, not a special-cased 403' );
};

test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/nonexistent-page-xyz-12345" );
    is( $res->code, 404, 'unknown URL returns the router-only 404' );
};

# An unrecognized /__rpc_* URI (the legacy AJAX mapping app.psgi used to
# special-case) falls through to the router's ordinary 404.
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/__rpc_this_is_not_a_real_endpoint" );
    is( $res->code, 404, "unknown /__rpc_* URI returns the router's 404" );
};

done_testing;
