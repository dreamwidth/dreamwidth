# t/lj-pagestats.t
#
# Test LJ::PageStats without loading ljlib.pl.
#
# Authors:
#      Alex Southwell <saphid@gmail.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use lib "$ENV{LJHOME}/cgi-bin";

use Test::More;
use HTTP::Request;
use DW::Request;
use DW::Request::Standard;
use LJ::ModuleLoader ();
use LJ::PageStats;
use LJ::User::Display     ();
use LJ::User::Login       ();
use LJ::User::Permissions ();

sub set_request {
    my ( $path, $cookie ) = @_;

    DW::Request->reset;
    my $request = HTTP::Request->new( GET => "http://example.test$path" );
    $request->header( Cookie => "ljuniq=$cookie" ) if defined $cookie;
    DW::Request::Standard->new($request);
}

my $stats = LJ::PageStats->new;

subtest 'request tracking eligibility' => sub {
    local $LJ::ACTIVE_JOURNAL;
    local $LJ::PAGESTATS_EXCLUDE{uripath} = [qr{^/private/}];

    DW::Request->reset;
    ok( !$stats->should_render, 'no request cannot be tracked' );

    set_request('/public/1');
    ok( !$stats->should_render, 'missing cookie does not permit tracking' );

    set_request( '/public/1', 'aBcDeFgHiJkLmNo:12345' );
    ok( !$stats->should_render, 'cookie without the tracking flag does not permit tracking' );

    set_request( '/public/1', 'aBcDeFgHiJkLmNo:12345:pgstats0' );
    ok( !$stats->should_render, 'tracking disabled in the cookie' );

    set_request( '/private/1', 'aBcDeFgHiJkLmNo:12345:pgstats1' );
    ok( !$stats->should_render, 'an excluded path overrides the enabled cookie' );

    set_request( '/public/1', 'aBcDeFgHiJkLmNo:12345:pgstats1' );
    ok( $stats->should_render, 'enabled cookie permits tracking on a public path' );

    DW::Request->reset;
};

subtest 'application tracker output' => sub {
    local $LJ::ACTIVE_JOURNAL;
    local $LJ::CACHED_REMOTE = 1;
    local $LJ::CACHE_REMOTE;
    local %LJ::SITE_PAGESTAT_CONFIG;

    is( $stats->render_head, '', 'unconfigured trackers emit no head markup' );
    unlike( $stats->render, qr{<script\b}, 'unconfigured trackers emit no body script' );

    $LJ::SITE_PAGESTAT_CONFIG{ga4_analytics} = 'G-PAGESTATS';
    like(
        $stats->render_head,
        qr{googletagmanager\.com/gtag/js\?id=G-PAGESTATS\b},
        'the configured GA4 tracker emits its script and measurement ID in the head'
    );
    unlike( $stats->render, qr{<script\b}, 'the head-only tracker emits no body script' );

    $LJ::SITE_PAGESTAT_CONFIG{google_analytics} = 'UA-12345-1';
    like(
        $stats->render,
        qr{google-analytics\.com/ga\.js},
        'the configured legacy tracker emits its loader in the body'
    );
};

subtest 'owner tracking opt-out' => sub {
    local $LJ::ACTIVE_JOURNAL;
    local $LJ::CACHED_REMOTE = 1;
    local $LJ::CACHE_REMOTE  = bless { userid => 101, exclude_from_own_stats => 1 }, 'LJ::User';
    my $own_journal   = bless { userid => 101 }, 'LJ::User';
    my $other_journal = bless { userid => 102 }, 'LJ::User';
    LJ::set_active_journal($own_journal);
    ok( !$stats->should_do_pagestats, 'opted-out owner is not tracked on their own journal' );
    is( $stats->render,      '', 'suppressed tracker emits no body markup' );
    is( $stats->render_head, '', 'suppressed tracker emits no head markup' );

    LJ::set_active_journal($other_journal);
    ok( $stats->should_do_pagestats, 'the preference does not suppress another journal' );

    LJ::set_active_journal(undef);
    ok( $stats->should_do_pagestats, 'the preference does not suppress application tracking' );

    LJ::set_active_journal($own_journal);
    $LJ::CACHE_REMOTE->{exclude_from_own_stats} = 0;
    ok( $stats->should_do_pagestats, 'own journal can be tracked without the opt-out' );

    $LJ::CACHE_REMOTE = undef;
    ok( $stats->should_do_pagestats, 'anonymous visitors are not subject to the owner opt-out' );
};

my @ljlib = grep { defined && m{(?:^|/)ljlib[.]pl\z} } ( keys %INC, values %INC );
is_deeply( \@ljlib, [], 'ljlib.pl was not loaded' );

done_testing;
