# t/external-sites-parsers.t
#
# Tests for external profile site parsers and link generation.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
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

use DW::External::User;
use DW::External::Site::ArtStation;
use DW::External::Site::Blogspot;
use DW::External::Site::DeviantArt;
use DW::External::Site::Etsy;
use DW::External::Site::Facebook;
use DW::External::Site::FanFiction;
use DW::External::Site::FurAffinity;
use DW::External::Site::Itch;
use DW::External::Site::KoFi;
use DW::External::Site::LastFM;
use DW::External::Site::Medium;
use DW::External::Site::Pinboard;
use DW::External::Site::Pinterest;
use DW::External::Site::Plurk;
use DW::External::Site::Ravelry;
use DW::External::Site::Substack;
use DW::External::Site::Tumblr;
use DW::External::Site::Wordpress;
use DW::External::Site::X;
use DW::External::Site::YouTube;

my @sites = (
    [
        'ArtStation',                         'artstation.com',
        'http://www.artstation.com/Sample42', 'http://www.artstation.com/Sample42/profile',
    ],
    [ 'Blogspot', 'blogspot.com', 'http://Sample42.blogspot.com', 'http://Sample42.blogspot.com', ],
    [
        'DeviantArt',                             'deviantart.com',
        'http://Sample42.deviantart.com/gallery', 'http://Sample42.deviantart.com',
    ],
    [
        'Etsy',                              'etsy.com',
        'http://www.etsy.com/shop/Sample42', 'http://www.etsy.com/people/Sample42',
    ],
    [
        'Facebook',                          'facebook.com',
        'https://www.facebook.com/Sample42', 'https://www.facebook.com/Sample42',
    ],
    [
        'FanFiction',                          'fanfiction.net',
        'http://www.fanfiction.net/~Sample42', 'http://www.fanfiction.net/~Sample42',
    ],
    [
        'FurAffinity',                                 'furaffinity.com',
        'http://www.furaffinity.com/gallery/Sample42', 'http://www.furaffinity.com/user/Sample42',
    ],
    [
        'Itch',                                'itch.io',
        'http://www.itch.io/profile/Sample42', 'http://www.itch.io/profile/Sample42',
    ],
    [ 'Kofi', 'ko-fi.com', 'http://www.ko-fi.com/Sample42', 'http://www.ko-fi.com/Sample42', ],
    [ 'LastFM', 'last.fm', 'http://last.fm/user/Sample42', 'http://last.fm/user/Sample42/charts', ],
    [
        'Medium',                              'medium.com',
        'https://medium.com/@Sample42/latest', 'https://medium.com/@Sample42',
    ],
    [
        'Pinboard',                          'pinboard.in',
        'http://www.pinboard.in/u:Sample42', 'http://www.pinboard.in/u:Sample42/profile/public',
    ],
    [
        'Pinterest',                         'pinterest.com',
        'http://www.pinterest.com/Sample42', 'http://www.pinterest.com/Sample42',
    ],
    [ 'Plurk', 'plurk.com', 'http://www.plurk.com/Sample42', 'http://www.plurk.com/Sample42', ],
    [
        'Ravelry',                                'ravelry.com',
        'http://www.ravelry.com/people/Sample42', 'http://www.ravelry.com/projects/Sample42',
    ],
    [
        'Substack',                      'substack.com',
        'http://Sample42.substack.com/', 'http://Sample42.substack.com/about',
    ],
    [ 'Tumblr', 'tumblr.com', 'http://Sample42.tumblr.com', 'http://Sample42.tumblr.com', ],
    [
        'Wordpress',                     'wordpress.com',
        'http://Sample42.wordpress.com', 'http://Sample42.wordpress.com',
    ],
    [ 'X', 'x.com', 'http://x.com/Sample42', 'http://x.com/Sample42' ],
    [
        'YouTube',                           'youtube.com',
        'https://www.youtube.com/@Sample42', 'https://www.youtube.com/@Sample42/about',
    ],
);

for my $case (@sites) {
    my ( $name, $domain, $journal_url, $profile_url ) = @$case;
    my $class = "DW::External::Site::$name";

    subtest $domain => sub {
        is( DW::External::User->new( site => $domain, user => 'Sample42/other' ),
            undef, 'reject a username containing a path' );

        my @labels = split /\./, $domain;
        is( $class->accepts( [ $labels[-1] ] ), undef, 'reject a single domain label' );

        my $user = DW::External::User->new( site => $domain, user => " \tSample42 \n" );
        isa_ok( $user, 'DW::External::User' ) or return;

        my $site = $user->site;
        isa_ok( $site, $class ) or return;
        is( $site->journal_url($user), $journal_url, 'journal URL' );
        is( $site->profile_url($user), $profile_url, 'profile URL' );

        my $parsed_site = $class->accepts( [ 'profiles', @labels ] );
        isa_ok( $parsed_site, $class ) or return;
        my $parsed_profile_url = $profile_url =~ s{://www\.}{://}r;
        is( $parsed_site->profile_url($user),
            $parsed_profile_url, 'links from parsed domains discard the input subdomain' );
    };
}

subtest 'Facebook username rules' => sub {
    my $user = DW::External::User->new( site => 'facebook.com', user => '  Sample.42  ' );
    isa_ok( $user, 'DW::External::User' ) or return;
    is(
        $user->site->profile_url($user),
        'https://www.facebook.com/Sample.42',
        'periods and case survive username normalization'
    );
    is( DW::External::User->new( site => 'facebook.com', user => 'Sample-42' ),
        undef, 'reject a hyphen even though most sites allow it' );
};

is_deeply(
    [ grep { defined && m{(?:^|/)ljlib\.pl\z} } ( keys %INC, values %INC ) ],
    [], 'the parser tests do not load ljlib.pl',
);

done_testing();
