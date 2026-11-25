#!/usr/bin/perl
#
# t/plack-root-static.t
#
# Root static files: allowlisted files are served, other htdocs paths are not,
# journal-host robots.txt reaches the per-journal controller, and an old .bml
# URL reaches its native route.
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

use Test::More;
use HTTP::Request::Common;
use Plack::Test;
use URI;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

test_psgi $app, sub {
    my $cb = shift;

    subtest 'allow-listed root-level files are served' => sub {
        for my $path ( '/robots.txt', '/favicon.ico', '/rte/blank.html' ) {
            is( $cb->( GET $path )->code, 200, "$path is 200" );
        }
        like( $cb->( GET '/500-error.html' )->content,
            qr/downforeveryoneorjustme/, 'ext/dw-nonfree overrides the base htdocs file' );
    };

    subtest 'other htdocs files stay unreachable' => sub {
        for my $path (
            '/inc/account-codes',  '/doc/.placeholder',
            '/preview/index.html', '/scss/foundation/normalize.scss',
            )
        {
            is( $cb->( GET $path )->code, 404, "$path is 404" );
        }
    };

    subtest 'an old .bml URL reaches its native route' => sub {
        my $res = $cb->( GET '/inbox/index.bml' );
        is( $res->code, 302, '/inbox/index.bml redirects anonymous visitors to login' );
        is(
            URI->new( $res->header('Location') // '' )->path_query,
            '/login?returnto=/inbox/index.bml',
            'the redirect comes from the native inbox handler'
        );
    };
};

subtest 'favicon.ico is served on a journal subdomain' => sub {
    local $LJ::USER_DOMAIN = 'example.org';
    local $LJ::DOMAIN_WEB  = 'www.example.org';
    local $LJ::DOMAIN      = 'example.org';

    test_psgi $app, sub {
        my $cb = shift;
        is( $cb->( GET 'http://someuser.example.org/favicon.ico' )->code,
            200, 'journal-host favicon.ico is 200' );
    };
};

subtest 'robots.txt on a journal host reaches Journal.pm, not the static file' => sub {
    local $LJ::USER_DOMAIN = 'example.org';
    local $LJ::DOMAIN_WEB  = 'www.example.org';
    local $LJ::DOMAIN      = 'example.org';

    my $blocked = temp_user();
    $blocked->update_self( { status => 'A' } );
    $blocked->set_prop( opt_blockrobots => 1 );

    test_psgi $app, sub {
        my $cb = shift;

        my $res = $cb->( GET 'http://' . $blocked->user . '.example.org/robots.txt' );
        is( $res->code, 200, "blocked journal's robots.txt is 200" );
        is(
            $res->content,
            "User-Agent: *\nDisallow: /\n",
            "blocked journal's robots.txt is Journal.pm's per-journal output"
        );

        like(
            $cb->( GET 'http://www.example.org/robots.txt' )->content,
            qr{Disallow: /directorysearch},
            "www's robots.txt is the static htdocs file"
        );
    };
};

done_testing;
