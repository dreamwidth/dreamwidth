#!/usr/bin/perl
#
# t/external-sites-atproto-archive.t
#
# Test handle parsing and account links for Atproto and archive sites.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
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
use DW::External::Site;
use DW::External::Site::Atproto;
use DW::External::Site::Bluesky;
use DW::External::Site::BlueskySocial;
use DW::External::Site::ArchiveofOurOwn;
use DW::External::Site::SquidgeWorld;
use DW::External::User;

subtest 'Atproto account overview' => sub {
    my $class = 'DW::External::Site::Atproto';
    ok( !$class->accepts( ['example'] ), 'rejects a single-label domain' );

    my $site = $class->accepts( [qw(writer example org)] );
    return unless isa_ok( $site, $class );

    my $user = DW::External::User->new( site => 'bsky', user => 'Writer.Example.ORG' );
    return unless isa_ok( $user, 'DW::External::User' );

    my $url = 'https://aturi.to/writer.example.org';
    is( $site->journal_url($user), $url, 'journal links to the whole account' );
    is( $site->profile_url($user), $url, 'profile links to the whole account' );
    is_deeply(
        $site->badge_image($user),
        { url => 'https://atproto.com/en/icon.ico', width => 16, height => 16 },
        'account badge uses the Atproto icon'
    );
};

subtest 'Bluesky uses a full handle' => sub {
    my $user = DW::External::User->new( site => 'bsky', user => "  Story-2.Writer.Example\t" );
    return unless isa_ok( $user, 'DW::External::User' );
    my $site = $user->site;
    isa_ok( $site, 'DW::External::Site::Bluesky' );
    is( $user->user, 'story-2.writer.example', 'trims and lowercases a custom-domain handle' );

    my $url = 'https://bsky.app/profile/story-2.writer.example';
    is( $site->journal_url($user), $url, 'journal uses the full handle' );
    is( $site->profile_url($user), $url, 'profile uses the full handle' );
    is_deeply(
        $site->badge_image($user),
        { url => 'https://web-cdn.bsky.app/static/favicon-16x16.png', width => 16, height => 16 },
        'profile badge uses the Bluesky icon'
    );

    for my $handle (qw(writer writer..example -writer.example writer-.example writer.1example)) {
        is( DW::External::User->new( site => 'bsky', user => $handle ),
            undef, "rejects malformed full handle '$handle'" );
    }
};

subtest 'Bluesky Social expands a short handle' => sub {
    my $user = DW::External::User->new( site => 'bsky.social', user => ' Writer-2 ' );
    return unless isa_ok( $user, 'DW::External::User' );
    my $site = $user->site;
    isa_ok( $site, 'DW::External::Site::BlueskySocial' );
    is( $user->user, 'writer-2.bsky.social', 'trims, lowercases, and adds the handle suffix' );
    is(
        $site->profile_url($user),
        'https://bsky.app/profile/writer-2.bsky.social',
        'expanded handle links to bsky.app, not bsky.social'
    );

    for my $handle (qw(writer.bsky.social writer.example writer_2 -writer writer-)) {
        is( DW::External::User->new( site => 'bsky.social', user => $handle ),
            undef, "rejects invalid short handle '$handle'" );
    }
};

for my $archive (
    [ 'ArchiveofOurOwn', 'archiveofourown.org', 'ao3', [qw(archiveofourown.org www.ao3.org)] ],
    [ 'Squidgeworld', 'squidgeworld.org', 'sqwa', [qw(squidgeworld.org www.squidgeworld.org)] ],
    )
{
    my ( $service, $domain, $alias, $hosts ) = @$archive;
    subtest "$service archive accounts" => sub {
        my $class = "DW::External::Site::$service";
        my $user  = DW::External::User->new( site => $alias, user => '  Story_Writer-2  ' );
        return unless isa_ok( $user, 'DW::External::User' );
        isa_ok( $user->site, $class, "site for '$alias'" );
        is( $user->user, 'Story_Writer-2', 'trims the username without changing its case' );

        for my $host (@$hosts) {
            my $site = $class->accepts( [ split /\./, $host ] );
            next unless isa_ok( $site, $class, "site for '$host'" );
            my $url = "https://$domain/users/Story_Writer-2/";
            is( $site->journal_url($user), $url, "'$host' uses the canonical archive host" );
            is( $site->profile_url($user), "${url}profile",
                "'$host' links to the archive profile" );
            is_deeply(
                $site->badge_image($user),
                { url => "https://$domain/favicon.ico", width => 16, height => 16 },
                "'$host' uses the canonical archive icon"
            );
        }

        ok(
            !$class->accepts( [ split /\./, "$domain.example" ] ),
            'rejects an unrelated domain with the archive name as a prefix'
        );
        ok( !$class->accepts( [qw(other org)] ), 'rejects an unrelated .org domain' );
        is( DW::External::User->new( site => $alias, user => 'writer/profile' ),
            undef, 'rejects a path instead of a username' );
    };
}

done_testing;
