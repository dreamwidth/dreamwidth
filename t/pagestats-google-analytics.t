#!/usr/bin/perl
#
# t/pagestats-google-analytics.t
#
# Test legacy Google Analytics and GA4 page statistics without loading ljlib.pl.
#
# Authors:
#     Alex Southwell <saphid@gmail.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use lib "$ENV{LJHOME}/extlib/lib/perl5", "$ENV{LJHOME}/cgi-bin";

use Test::More;
use DW::PageStats::GoogleAnalytics;
use DW::PageStats::GoogleAnalytics4;
use LJ::Capabilities      ();
use LJ::Hooks             ();
use LJ::ModuleLoader      ();
use LJ::PageStats         ();
use LJ::TextUtil          ();
use LJ::User::Display     ();
use LJ::User::Login       ();
use LJ::User::Permissions ();

local $LJ::ACTIVE_JOURNAL;
local $LJ::CACHED_REMOTE = 1;
local $LJ::CACHE_REMOTE;
local %LJ::SITE_PAGESTAT_CONFIG;

my $stats = LJ::PageStats->new;

{
    local $LJ::SITE_PAGESTAT_CONFIG{google_analytics} = 'UA-12345-1';

    my $head = $stats->render_head;
    like(
        $head,
        qr{_gaq\.push\(\['_setAccount',\s*'UA-12345-1'\]\)},
        'legacy tracker sets the site account'
    );
    like( $head, qr{_gaq\.push\(\['_trackPageview'\]\)}, 'legacy tracker queues a pageview' );
    unlike( $head, qr{\bgtag\b}, 'legacy site configuration does not enable GA4' );
    like(
        $stats->render,
        qr{['"]\.google-analytics\.com/ga\.js['"]},
        'legacy tracker loads ga.js in the body'
    );
}

{
    local $LJ::SITE_PAGESTAT_CONFIG{ga4_analytics} = 'G-SITE123';

    my $head = $stats->render_head;
    like(
        $head,
        qr{src="https://www\.googletagmanager\.com/gtag/js\?id=G-SITE123"},
        'GA4 loads gtag.js over HTTPS with the site measurement ID'
    );
    like(
        $head,
        qr{\bgtag\('config',\s*'G-SITE123'\)},
        'GA4 configures the same site measurement ID'
    );
    unlike( $head, qr{\b_gaq\b}, 'GA4 site configuration does not enable the legacy tracker' );
    unlike( $stats->render, qr{<script\b}, 'GA4 does not emit a body script' );
}

{
    local %LJ::SITE_PAGESTAT_CONFIG = (
        google_analytics => 'UA-12345-1',
        ga4_analytics    => 'G-SITE123',
    );
    local %LJ::CAP;
    local $LJ::CAP_DEF{google_analytics} = 0;
    local $LJ::T_HAS_ALL_CAPS            = 1;
    local $LJ::ACTIVE_JOURNAL            = bless {
        userid           => 101,
        caps             => 0,
        google_analytics => 'UA-98765-2',
        ga4_analytics    => 'G-JOURNAL123',
        },
        'LJ::User';

    my $head = $stats->render_head;
    like(
        $head,
        qr{_gaq\.push\(\['_setAccount',\s*'UA-98765-2'\]\)},
        'legacy tracker uses the journal account'
    );
    like(
        $head,
        qr{src="https://www\.googletagmanager\.com/gtag/js\?id=G-JOURNAL123"},
        'GA4 script URL uses the journal measurement ID'
    );
    like(
        $head,
        qr{\bgtag\('config',\s*'G-JOURNAL123'\)},
        'GA4 configures the journal measurement ID'
    );
    unlike( $head, qr{UA-12345-1|G-SITE123}, 'journal tracking does not include site IDs' );

    {
        local $LJ::ACTIVE_JOURNAL->{google_analytics} = '';
        my $head = $stats->render_head;
        unlike( $head, qr{\b_gaq\b},
            'an empty journal legacy ID does not fall back to the site ID' );
        like( $head, qr{\bgtag\('config',\s*'G-JOURNAL123'\)}, 'the journal GA4 ID still works' );
        unlike( $stats->render, qr{ga\.js}, 'no legacy loader without a journal legacy ID' );
    }

    {
        local $LJ::ACTIVE_JOURNAL->{ga4_analytics} = undef;
        my $head = $stats->render_head;
        unlike( $head, qr{\bgtag\b}, 'an unset journal GA4 ID does not fall back to the site ID' );
        like( $head, qr{_setAccount',\s*'UA-98765-2'}, 'the journal legacy ID still works' );
    }

    {
        local $LJ::T_HAS_ALL_CAPS = 0;
        is( $stats->render_head, '', 'a journal without the capability emits neither tracker' );
        unlike( $stats->render, qr{<script\b}, 'a journal without the capability emits no loader' );
    }

    {
        local $LJ::ACTIVE_JOURNAL->{google_analytics} = q{UA-old'1};
        local $LJ::ACTIVE_JOURNAL->{ga4_analytics}    = q{G-old'1};
        my $head = $stats->render_head;
        like( $head, qr{_setAccount',\s*'UA-old\\'1'}, 'legacy tracker escapes stored JS quotes' );
        like( $head, qr{\bgtag\('config',\s*'G-old\\'1'\)}, 'GA4 escapes stored JS quotes' );
    }

    {
        local $LJ::CACHE_REMOTE = bless { userid => 101, exclude_from_own_stats => 1 }, 'LJ::User';
        is( $stats->render_head, '', 'an opted-out owner sees neither tracker on their journal' );
        is( $stats->render, '', 'an opted-out owner also sees no body tracker on their journal' );
    }
}

my @ljlib = grep { defined && m{(?:^|/)ljlib[.]pl\z} } ( keys %INC, values %INC );
is_deeply( \@ljlib, [], 'ljlib.pl was not loaded' );

done_testing;
