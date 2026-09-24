#!/usr/bin/perl
#
# t/plack-no-bml-fallback.t
#
# Locks the request-dispatch fallback chain (DW::Routing -> journal routing ->
# DW::BML resolve_path/render -> 404) that app.psgi's _handle_request builds
# today, so E3's engine deletion can prove it preserved every branch.
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

plan skip_all => 'BML fallback characterization requires a development server'
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
        unlike(
            $res->content,
            qr/^Not Found$/,
            'body is not DW::BML::render\'s bare 404 fallback body'
        );
    };

    subtest '_config.bml is never served from any overlay directory' => sub {

        # htdocs/_config.bml and ext/dw-nonfree/htdocs/_config-local.bml are
        # both reachable through LJ::get_all_directories('htdocs')'s overlay
        # search, at the URLs below (the overlay extends the search path, not
        # the URL namespace -- there is no literal /ext/ URL prefix). Asserted
        # as "not 200 and no leaked directive" rather than the current literal
        # 403, so this holds whether the request is rejected by DW::BML::
        # render's _config check (today) or simply falls through to the
        # router's 404 once the engine is gone (after E3) -- either way, the
        # file's contents must never reach the response.
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

    subtest '/update GET still redirects legacy posting links to the native form' => sub {
        my $res = $cb->( GET '/update?subject=hello' );
        is( $res->code, 302, '/update?subject=hello status is 302' );
        is( location_path_query($res),
            '/entry/new?subject=hello',
            '/update redirects to /entry/new carrying the subject arg' );

        my $suffixed_res = $cb->( GET '/update.bml?subject=hello' );
        is( $suffixed_res->code, 302, '/update.bml?subject=hello status is 302' );
        is( location_path_query($suffixed_res),
            '/entry/new?subject=hello',
            '/update.bml reaches the same handler as /update, .bml stripped before matching' );
    };
};

done_testing;
