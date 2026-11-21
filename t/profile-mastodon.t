#!/usr/bin/perl
#
# t/profile-mastodon.t
#
# Test Mastodon links on user profiles.
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
use DW::Logic::ProfilePage;
use LJ::Test qw( temp_user );

my %services = map { $_->{name} => $_ } @{ DW::External::ProfileServices->list };
my $mastodon = $services{mastodon};
unless ( ok( $mastodon, 'Mastodon is available in Other Sites' ) ) {
    done_testing();
    exit;
}

my $owner = temp_user();
ok(
    $owner->save_profile_accts(
        { $mastodon->{service_id} => [ '@alice@social.example', 'bob@other.example' ] }
    ),
    'can save multiple Mastodon accounts'
);

my $profile = $owner->profile_page( $owner, viewall => 1 );
is_deeply(
    [ sort map { $_->{url} } @{ $profile->external_services } ],
    [ 'https://other.example/@bob', 'https://social.example/@alice' ],
    'each account links to its own instance and username'
);

for my $invalid ( 'alice', '@other.example', 'alice@other.example/path', 'alice@bad-.example' ) {
    ok( !DW::External::ProfileServices->account_url( $mastodon, $invalid ),
        "does not create a profile link for $invalid" );
}

my $accounts = $owner->load_profile_accts->{ $mastodon->{service_id} };
$owner->save_profile_accts(
    {
        $services{patreon}->{service_id} =>
            [ [ $accounts->[0][0], 'alice' ], [ $accounts->[1][0], '' ] ]
    }
);
is_deeply( $owner->load_profile_accts->{ $mastodon->{service_id} },
    $accounts, 'a submission for another service cannot update or delete Mastodon accounts' );

done_testing();
