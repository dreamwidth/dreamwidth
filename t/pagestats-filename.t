#!/usr/bin/perl
# PageStats has no filesystem filename in native requests or outside a request.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;

use Test::More;
use HTTP::Request::Common qw(GET);
use Plack::Test;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::PageStats::GoogleAnalytics;
use DW::PageStats::GoogleAnalytics4;
use DW::Request;
use DW::Request::Plack;
use LJ::PageStats;

subtest 'filename() is undef inside a real request' => sub {
    test_psgi(
        app => sub {
            my $env = shift;
            DW::Request->reset;
            DW::Request->get( plack_env => $env );
            my $filename = LJ::PageStats->new->filename;
            return [
                200,
                [ 'Content-Type' => 'text/plain' ],
                [ defined $filename ? "DEFINED:$filename" : 'UNDEF' ]
            ];
        },
        client => sub {
            my $cb  = shift;
            my $res = $cb->( GET '/' );
            is( $res->content, 'UNDEF', 'filename() is undef for a native request' );
        },
    );
    DW::Request->reset;
};

subtest 'filename() is undef, not a crash, outside any request' => sub {
    DW::Request->reset;
    ok( !DW::Request->get, 'fixture confirms no active request' );

    my $filename;
    my $ok = eval { $filename = LJ::PageStats->new->filename; 1 };
    ok( $ok, 'filename() does not die with no active request' )
        or diag("died with: $@");
    is( $filename, undef, 'filename() returns undef with no active request' );
};

subtest 'GA and GA4 output is unaffected by whatever filename() returns' => sub {
    local %LJ::SITE_PAGESTAT_CONFIG = (
        google_analytics => 'UA-test-1',
        ga4_analytics    => 'G-TEST1',
    );

    my $ga_head_before  = DW::PageStats::GoogleAnalytics->new->_render_head;
    my $ga_body_before  = DW::PageStats::GoogleAnalytics->new->_render;
    my $ga4_head_before = DW::PageStats::GoogleAnalytics4->new->_render_head;
    my $ga4_body_before = DW::PageStats::GoogleAnalytics4->new->_render;

    ok( length $ga_head_before,  'fixture: GA head output is actually non-empty' );
    ok( length $ga4_head_before, 'fixture: GA4 head output is actually non-empty' );

    no warnings 'redefine';
    local *LJ::PageStats::filename = sub { return '/some/bogus/path.bml' };

    is( DW::PageStats::GoogleAnalytics->new->_render_head,
        $ga_head_before, 'GA head output unchanged when filename() returns a bogus value' );
    is( DW::PageStats::GoogleAnalytics->new->_render,
        $ga_body_before, 'GA body output unchanged when filename() returns a bogus value' );
    is( DW::PageStats::GoogleAnalytics4->new->_render_head,
        $ga4_head_before, 'GA4 head output unchanged when filename() returns a bogus value' );
    is( DW::PageStats::GoogleAnalytics4->new->_render,
        $ga4_body_before, 'GA4 body output unchanged when filename() returns a bogus value' );
};

done_testing;
