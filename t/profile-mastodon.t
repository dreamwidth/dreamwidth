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

use HTTP::Request::Common;
use Plack::Test;
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

subtest 'invalid profile submissions do not save Other Sites accounts' => sub {
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'profileMastodonTest';
    my $editor = temp_user();
    my $app    = do "$ENV{LJHOME}/app.psgi";
    die $@ unless ref $app eq 'CODE';

    my $url    = 'http://localhost/manage/profile?as=' . $editor->user;
    my %fields = (
        name              => 'Profile owner',
        extservice_site_1 => $mastodon->{service_id},
        extservice_val_1  => 'retry@social.example',
        extservice_site_2 => $services{patreon}->{service_id},
        extservice_val_2  => 'retry',
        interests => join( ', ', map { "interest $_" } 1 .. $editor->count_max_interests + 1 ),
    );
    $fields{LJ__Setting__FindByEmail_opt_findbyemail} = 'N';

    test_psgi $app, sub {
        my ($request) = @_;
        my $form      = $request->( GET $url );
        my ($token)   = $form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        ok( $token, 'received a profile form token' ) or return;

        my $original_name = $editor->{name};
        my %invalid       = ( %fields, extservice_val_1 => 'retry', interests => 'gardening' );
        my $invalid_handle =
            $request->( POST $url, Content => [ %invalid, lj_form_auth => $token ] );
        is( $invalid_handle->code, 200, 'an incomplete handle returns the editor' );
        is( LJ::load_userid( $editor->id, 1 )->{name},
            $original_name, 'an incomplete handle leaves the profile name unchanged' );
        is_deeply( $editor->load_profile_accts( force_db => 1 ),
            {}, 'an incomplete handle prevents saving either service' );

        my $rejected = $request->( POST $url, Content => [ %fields, lj_form_auth => $token ] );
        is( $rejected->code, 200, 'excess interests return the editor' );
        like(
            $rejected->content,
            qr/<textarea(?=[^>]*\bname=['"]interests['"])[^>]*\bclass=['"][^'"]*\berror\b/,
            'the editor marks the interests field as invalid'
        );
        like(
            $rejected->content,
            qr/<input(?=[^>]*\bname="extservice_val_1")[^>]*\bvalue="retry\@social\.example"/,
            'rejected form retains the new handle'
        );
        is_deeply( $editor->load_profile_accts( force_db => 1 ),
            {}, 'rejected form does not save either service' );

        ($token) = $rejected->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        ok( $token, 'received a token for the retry' ) or return;
        $fields{interests} = 'gardening';
        my $accepted = $request->( POST $url, Content => [ %fields, lj_form_auth => $token ] );
        ok( $accepted->is_redirect, 'corrected submission redirects to the profile' );
        is_deeply( [ keys %{ $editor->interests( { forceids => 1 } ) } ],
            ['gardening'], 'the corrected interests are saved' );

        my $saved = $editor->load_profile_accts( force_db => 1 );
        for my $service ( $mastodon, $services{patreon} ) {
            my $expected = $service == $mastodon ? 'retry@social.example' : 'retry';
            is_deeply( [ map { $_->[1] } @{ $saved->{ $service->{service_id} } || [] } ],
                [$expected], "saved exactly one $service->{name} account" );
        }
    };
};

done_testing();
