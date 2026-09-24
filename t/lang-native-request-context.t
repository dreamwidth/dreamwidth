#!/usr/bin/perl
#
# t/lang-native-request-context.t
#
# Locks what Plack::Middleware::DW::RequestWrapper establishes for every
# native request's language context: a *starting* language/getter only --
# it reads no cookie or Accept-Language header itself. A visitor's actual
# negotiated language is established later, by a controller or the ml TT
# filter's uselang handling, calling LJ::Lang::set_request_context(lang=>...)
# again. This test locks both stages: RequestWrapper's starting context, and
# that LJ::Lang::ml keeps resolving correctly once a later stage renegotiates
# to a different language code.
#
# This test DB has no non-"en" language loaded via texttool.pl (only "en" and
# "en_DW" are in ml_langs), so "en_DW" stands in for "a non-en language code"
# below: it is genuinely DB-backed (not a stub getter), even though its text
# happens to fall back to the same English content via childrenlatest.
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use LJ::Lang;
use Plack::Middleware::DW::RequestWrapper;

sub run_wrapped {
    my ($code) = @_;
    open my $input, '<', \( my $body = '' ) or die $!;
    my $app = Plack::Middleware::DW::RequestWrapper->wrap(
        sub {
            $code->();
            DW::Request->get->status(200);
            return DW::Request->get->res;
        }
    );
    return $app->(
        {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/',
            QUERY_STRING      => '',
            SERVER_NAME       => 'localhost',
            SERVER_PORT       => 80,
            HTTP_HOST         => 'localhost',
            'psgi.version'    => [ 1, 1 ],
            'psgi.url_scheme' => 'http',
            'psgi.input'      => $input,
            'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh },
        }
    );
}

subtest 'RequestWrapper establishes DEFAULT_LANG and the native getter as the starting context' =>
    sub {
    local $LJ::DEFAULT_LANG = 'en_DW';

    # Pinned distinct from DEFAULT_LANG: RequestWrapper falls back to
    # $LJ::LANGS[0] only when DEFAULT_LANG is unset, so if the two ever
    # matched in a given environment's config, this assertion couldn't tell
    # which one RequestWrapper actually read.
    local @LJ::LANGS = ('en');
    my ( $context, $ml_result );
    run_wrapped(
        sub {
            $context   = LJ::Lang::request_context();
            $ml_result = LJ::Lang::ml('/entry/preview.tt.title');
        }
    );
    ok( $context, 'a request context exists once RequestWrapper has run' );
    is( $context->{lang}, 'en_DW',
        'starting lang is $LJ::DEFAULT_LANG, not $LJ::LANGS[0] or a cookie/header' );
    is( $context->{getter}, \&LJ::Lang::get_text,
        'starting getter is exactly \&LJ::Lang::get_text (by reference)' );
    is(
        $ml_result,
        LJ::Lang::get_text( 'en_DW', '/entry/preview.tt.title' ),
        'ml() on a .tt key resolves through that same getter at the starting language'
    );
    };

subtest
    'ml keeps resolving a .tt key correctly once a later stage renegotiates to a different language'
    => sub {
    local $LJ::DEFAULT_LANG = 'en';
    my ( $before, $context_after, $after, $direct );
    run_wrapped(
        sub {
            $before = LJ::Lang::ml('/entry/preview.tt.title');

            # Simulates what a controller or the ml TT filter's uselang
            # handling does later in a real request: renegotiate lang without
            # touching the getter RequestWrapper installed.
            LJ::Lang::set_request_context( lang => 'en_DW' );
            $context_after = LJ::Lang::request_context();
            $after         = LJ::Lang::ml('/entry/preview.tt.title');
            $direct        = LJ::Lang::get_text( 'en_DW', '/entry/preview.tt.title' );
        }
    );
    is(
        $before,
        LJ::Lang::get_text( 'en', '/entry/preview.tt.title' ),
        'before renegotiation, ml() resolves at the starting (en) language'
    );

    # en and en_DW happen to render identical text here (en_DW falls back to
    # English via childrenlatest), so $after/$direct/$before alone couldn't
    # tell a real renegotiation from a no-op -- assert directly on the
    # context object instead.
    is( $context_after->{lang},
        'en_DW', 'the renegotiation actually changed the context lang to en_DW' );
    is( $context_after->{getter},
        \&LJ::Lang::get_text,
        'the renegotiation left the RequestWrapper-installed getter untouched' );
    is( $after, $direct,
        'after renegotiation, ml() resolves the same .tt key through the en_DW-language getter call'
    );
    ok( !LJ::Lang::is_missing_string($after),
        'the renegotiated language genuinely resolved through the DB, not a missing-string fallback'
    );
    };

done_testing;
