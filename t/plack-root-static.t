#!/usr/bin/perl
#
# t/plack-root-static.t
#
# Root static files: the allowlisted files are served with correct types,
# other htdocs paths are not, and journal-host robots.txt reaches the
# per-journal controller.
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

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

test_psgi $app, sub {
    my $cb = shift;

    subtest 'allow-listed root-level files and rte/ assets are served with the right type' => sub {
        for my $case (
            [ '/robots.txt',           qr{^text/plain} ],
            [ '/favicon.ico',          qr{^image/(?:vnd\.microsoft\.icon|x-icon)} ],
            [ '/apple-touch-icon.png', qr{^image/png} ],
            [ '/protocol.dat',         qr{^text/plain} ],
            [ '/500-error.html',       qr{^text/html} ],
            [ '/rte/blank.html',       qr{^text/html} ],
            [ '/rte/index.html',       qr{^text/html} ],
            [ '/rte/palette.html',     qr{^text/html} ],
            )
        {
            my ( $path, $type ) = @$case;
            my $res = $cb->( GET $path );
            is( $res->code, 200, "$path is 200" );
            like( $res->header('Content-Type') // '', $type,
                "$path has the expected content type" );
        }
    };

    subtest '500-error.html is served from the dw-nonfree overlay, not the base file' => sub {
        my $res = $cb->( GET '/500-error.html' );
        is( $res->code, 200, '/500-error.html is 200' );
        like( $res->content, qr/downforeveryoneorjustme/,
            'overlay priority still favors ext/dw-nonfree over the base htdocs file' );
    };

    subtest 'the old blanket fallback\'s excluded paths stay unreachable' => sub {
        for my $path (
            '/inc/account-codes',  '/doc/.placeholder',
            '/preview/index.html', '/scss/foundation/normalize.scss',
            )
        {
            my $res = $cb->( GET $path );
            is( $res->code, 404, "$path is still 404" );
        }
    };
};

subtest 'favicon.ico is served on a journal subdomain, not just the site host' => sub {
    local $LJ::USER_DOMAIN = 'example.org';
    local $LJ::DOMAIN_WEB  = 'www.example.org';
    local $LJ::DOMAIN      = 'example.org';

    test_psgi $app, sub {
        my $cb  = shift;
        my $res = $cb->( GET 'http://someuser.example.org/favicon.ico' );
        is( $res->code, 200, 'journal-host favicon.ico is 200' );
        like(
            $res->header('Content-Type') // '',
            qr{^image/(?:vnd\.microsoft\.icon|x-icon)},
            'journal-host favicon.ico has the expected content type'
        );
    };
};

subtest 'robots.txt on a journal host reaches Journal.pm, not the static allowlist' => sub {
    local $LJ::USER_DOMAIN = 'example.org';
    local $LJ::DOMAIN_WEB  = 'www.example.org';
    local $LJ::DOMAIN      = 'example.org';

    local $LJ::HOOKS{robots_txt_extra} = [ sub { return "# extra line\n" } ];

    my $ordinary = temp_user();
    $ordinary->update_self( { status => 'A' } );

    my $blocked = temp_user();
    $blocked->update_self( { status => 'A' } );
    $blocked->set_prop( opt_blockrobots => 1 );

    test_psgi $app, sub {
        my $cb = shift;

        my $res = $cb->( GET 'http://' . $ordinary->user . '.example.org/robots.txt' );
        is( $res->code, 200, "ordinary journal's robots.txt is 200" );
        is(
            $res->content,
            "# extra line\nUser-Agent: *\n",
"ordinary journal's robots.txt matches Journal.pm's own output, including robots_txt_extra"
        );

        my $blocked_res = $cb->( GET 'http://' . $blocked->user . '.example.org/robots.txt' );
        is( $blocked_res->code, 200, "blocked journal's robots.txt is 200" );
        is(
            $blocked_res->content,
            "# extra line\nUser-Agent: *\nDisallow: /\n",
            "blocked journal's robots.txt is Journal.pm's own output with a bare Disallow: / line"
        );

        my $site_res = $cb->( GET 'http://www.example.org/robots.txt' );
        is( $site_res->code, 200, "www's robots.txt is 200" );
        like(
            $site_res->content,
            qr{Disallow: /directorysearch},
            "www's robots.txt is the static htdocs file, not Journal.pm's per-journal output"
        );
    };
};

done_testing;
