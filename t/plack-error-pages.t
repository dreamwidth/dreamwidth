#!/usr/bin/perl
# t/plack-error-pages.t
#
# Tests that error HTTP statuses render real error-document bodies through the
# full Plack stack, rather than the empty responses browsers replace with their
# own generic error page. Mirrors Apache's ErrorDocument handling.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
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

BEGIN {
    $LJ::_T_CONFIG = 1;
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

# Load the Plack app
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Test: a missing page returns a non-empty 404 body (not a blank response).
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "http://localhost/nonexistent-page-xyz-12345" );

    is( $res->code, 404, "Missing page returns 404" );
    like( $res->header('Content-Type'), qr{text/html}, "404 body is HTML" );
    ok( length( $res->content ), "404 response has a non-empty body" );
    like( $res->content, qr/find that page/i, "404 body is the stock error page" );
};

# Test: HEAD on a missing page returns 404 with no body but a non-zero
# Content-Length (the Head middleware strips the body but, sitting outside
# ContentLength, leaves the header reflecting what GET would have returned).
# (An exact match against GET's length would be flaky: the stock 404 page
# embeds a randomly chosen quip, so its length varies between requests.)
test_psgi $app, sub {
    my $cb   = shift;
    my $head = $cb->( HEAD "http://localhost/nonexistent-page-xyz-12345" );

    is( $head->code,    404, "HEAD of missing page returns 404" );
    is( $head->content, "",  "HEAD response has no body" );
    cmp_ok( $head->header('Content-Length'), '>', 0, "HEAD keeps a non-zero Content-Length" );
};

done_testing;
