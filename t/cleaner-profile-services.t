#!/usr/bin/perl
#
# t/cleaner-profile-services.t
#
# Test user-tag links for services already available on profiles.
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

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::External::ProfileServices;
use DW::External::Site;
use DW::External::User;
use LJ::CleanHTML;

my @services = (
    [
        'pillowfort', 'Pillowfort', 'pillowfort.social',
        'https://www.pillowfort.social/Example_3057',
        [qw(pillowfort pf pillowfort.social www.pillowfort.social)]
    ],
    [
        'patreon', 'Patreon', 'patreon.com',
        'https://www.patreon.com/Example_3057',
        [qw(patreon patreon.com www.patreon.com)]
    ],
    [
        'reddit', 'Reddit', 'reddit.com',
        'https://www.reddit.com/user/Example_3057',
        [qw(reddit reddit.com www.reddit.com)]
    ],
    [
        'wattpad', 'Wattpad', 'wattpad.com',
        'https://www.wattpad.com/user/Example_3057',
        [qw(wattpad wattpad.com www.wattpad.com)]
    ],
);

my %profile_services = map { $_->{name} => $_ } @{ DW::External::ProfileServices->list };

for my $service (@services) {
    my ( $name, $class, $domain, $url, $aliases ) = @$service;

    subtest $name => sub {
        my $profile = $profile_services{$name};
        ok( $profile, 'existing profile service is present' );
        if ($profile) {
            is( 'https:' . sprintf( $profile->{url_format}, 'Example_3057' ),
                $url, 'user-tag destination matches the profile service' );
        }

        for my $alias (@$aliases) {
            subtest $alias => sub {
                my $u = DW::External::User->new( user => ' Example_3057 ', site => $alias );
                ok( $u, 'user tag resolves' );
                return unless $u;

                isa_ok( $u->site, "DW::External::Site::$class" );
                is( $u->site->{domain}, $domain, 'canonical domain' );
                is( $u->user, 'Example_3057', 'trim whitespace and retain username case' );
                is( $u->site->journal_url($u), $url, 'username destination' );
                is( $u->site->profile_url($u), $url, 'profile icon destination' );
                is( DW::External::Site->get_site_by_id( $u->site->{siteid} ),
                    $u->site, 'registered site ID resolves to this service' );

                for my $source (
                    qq{<lj user="Example_3057" site="$alias">},
                    qq{<user name="Example_3057" site="$alias">},
                    '@Example_3057.' . $alias
                    )
                {
                    # Use the real cleaner and resolver: ljtestlib.pl mocks external users.
                    my $html = $source;
                    LJ::CleanHTML::clean_event( \$html, { editor => 'html_casual1' } );
                    my @links = $html =~ /<a href=['"]\Q$url\E['"]/g;
                    is( scalar @links, 2, "$source links both icon and username" );
                    like( $html, qr{<b>Example_3057</b>},          'renders the username' );
                    like( $html, qr{\Q/profile_icons/$name.png\E}, 'uses the existing local icon' );
                }
            };
        }

        for my $invalid ( q{bad'name}, 'bad/name', 'bad?name', '<bad>' ) {
            ok(
                !DW::External::User->new( user => $invalid, site => $name ),
                'reject username punctuation that could change the link or markup'
            );
        }

        my $markdown = '@Example_3057.' . $name;
        LJ::CleanHTML::clean_event( \$markdown, { editor => 'markdown0' } );
        my @markdown_links = $markdown =~ /<a href=['"]\Q$url\E['"]/g;
        is( scalar @markdown_links, 2, 'Markdown mention links both icon and username' );

        my $site = DW::External::Site->get_site( site => uc $name );
        ok( $site && $site->{domain} eq $domain, 'service names are case insensitive' );
        my @crosspost = grep { $_->{domain} eq $domain } DW::External::Site->get_xpost_sites;
        is( scalar @crosspost, 0, 'linking does not enable crossposting' );
    };
}

done_testing();
