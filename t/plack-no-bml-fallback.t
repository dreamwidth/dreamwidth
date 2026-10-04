#!/usr/bin/perl
#
# t/plack-no-bml-fallback.t
#
# Request dispatch in app.psgi's _handle_request: DW::Routing, then journal
# routing, then the router's 404 page. Covers the 404 fallback, that _config.bml
# files are never served, and that a .bml suffix reaches the native handler.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use warnings;

use HTTP::Request::Common;
use Plack::Test;
use Test::More;
use URI;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

plan skip_all => 'dispatch fallback tests require a development server'
    unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

# Scheme/host varies with how the harness constructs the request; only the
# path+query the redirect carries is under test here.
sub location_path_query {
    my ($res) = @_;
    my $location = $res->header('Location');
    return undef unless defined $location;
    return URI->new($location)->path_query;
}

test_psgi $app, sub {
    my $cb = shift;

    subtest 'an unknown URL falls through to the router\'s own 404 page' => sub {
        my $res = $cb->( GET '/this-path-definitely-does-not-exist-w13-precheck' );
        is( $res->code, 404, 'status is 404' );
        like( $res->header('Content-Type'), qr{^text/html}, 'content type is html' );
        like(
            $res->content,
            qr/Page not found/,
            'body is the routed internal 404 page (app.psgi\'s _render_error_document)'
        );
    };

    subtest '_config.bml is never served from any overlay directory' => sub {

        # htdocs/_config.bml and ext/dw-nonfree/htdocs/_config-local.bml sit in
        # the htdocs overlay directories at the URLs below (the overlay extends
        # the search path, not the URL namespace). Their directives must never
        # reach a response.
        for my $path (qw(/_config.bml /_config-local.bml)) {
            my $res = $cb->( GET $path );
            isnt( $res->code, 200, "$path is never served with a 200" );
            unlike(
                $res->content,
                qr/LookRoot|ExtraConfig|DefaultScheme/,
                "$path response body leaks none of the file's directives"
            );
        }
    };

    subtest 'a .bml suffix on a native page strips via DW::Routing, reaching the same handler' =>
        sub {
        my $bare_res = $cb->( GET '/inbox/index' );
        is( $bare_res->code, 302, '/inbox/index (anonymous) redirects to login' );
        is(
            location_path_query($bare_res),
            '/login?returnto=/inbox/index',
            '/inbox/index redirect carries its own path as returnto'
        );

        my $suffixed_res = $cb->( GET '/inbox/index.bml' );
        is( $suffixed_res->code, 302, '/inbox/index.bml (anonymous) redirects to login too' );
        is( location_path_query($suffixed_res), '/login?returnto=/inbox/index.bml',
'/inbox/index.bml reaches the same require-login handler as /inbox/index, .bml stripped before matching'
        );
        };
};

done_testing;
