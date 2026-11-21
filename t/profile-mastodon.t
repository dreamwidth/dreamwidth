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

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

subtest 'invalid profile submissions do not save Other Sites accounts' => sub {
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'profileMastodonTest';
    my $editor = temp_user();

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

sub _parse_extservice_rows {
    my ($html) = @_;
    my %fields;
    my %errors;

    while ( $html =~ /<input\b([^>]+)>/gi ) {
        my $attrs = $1;
        my ($name) = $attrs =~ /\bname=['"](extservice_(?:site|dbid|val)_\d+)['"]/i;
        next unless $name;
        my ($val) = $attrs =~ /\bvalue=['"]([^'"]*)['"]/i;
        $fields{$name} = defined $val ? $val : '';
        $errors{$name} = 1 if $attrs =~ /\bclass=['"][^'"]*\berror\b/i;
    }

    while ( $html =~ /<select\b([^>]+)>(.*?)<\/select>/gis ) {
        my ( $attrs, $body ) = ( $1, $2 );
        my ($name) = $attrs =~ /\bname=['"](extservice_site_\d+)['"]/i;
        next unless $name;
        my ($sel) = $body =~ /<option\b(?=[^>]*\bselected\b)[^>]*\bvalue=['"]([^'"]*)['"]/i;
        $fields{$name} = defined $sel ? $sel : '';
    }

    my %by_dbid;
    foreach my $ct ( 1 .. 26 ) {
        my $dbid = $fields{"extservice_dbid_$ct"};
        next unless defined $dbid && $dbid ne '';
        $by_dbid{$dbid} = {
            ct    => $ct,
            site  => $fields{"extservice_site_$ct"} // '',
            value => $fields{"extservice_val_$ct"} // '',
            error => $errors{"extservice_val_$ct"} ? 1 : 0,
        };
    }

    return ( \%fields, \%by_dbid );
}

subtest 'rejected edits keep account identities across intervening DB changes' => sub {
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'profileMastodonReorderTest';

    my $form_token = sub {
        my ($html)  = @_;
        my ($token) = $html =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
        return $token;
    };

    test_psgi $app, sub {
        my ($request) = @_;

        # 1. Two preexisting Mastodon accounts, intervening reorder, rejected
        # POST clearing row 1, then corrected retry must delete only row 1.
        {
            my $editor = temp_user();
            my $url    = 'http://localhost/manage/profile?as=' . $editor->user;
            my $m_id   = $mastodon->{service_id};

            $editor->save_profile_accts(
                { $m_id => [ 'alice@social.example', 'bob@other.example' ] } );
            my $saved = $editor->load_profile_accts( force_db => 1 )->{$m_id};
            my ( $alice_id, $bob_id ) = map { $_->[0] } @$saved;

            my $form  = $request->( GET $url );
            my $token = $form_token->( $form->content );
            ok( $token, 'received token for Mastodon reorder test' ) or return;
            my ( $fields, $by_dbid ) = _parse_extservice_rows( $form->content );
            is( $by_dbid->{$alice_id}{ct}, 1, 'initial form places alice in slot 1' );
            is( $by_dbid->{$bob_id}{ct},   2, 'initial form places bob in slot 2' );

            # Another tab edits Alice so Bob now sorts first in the DB.
            $editor->save_profile_accts( { $m_id => [ [ $alice_id, 'zoe@social.example' ] ] } );

            my %post = (
                %$fields,
                name                                     => 'Profile owner',
                LJ__Setting__FindByEmail_opt_findbyemail => 'N',
                extservice_val_1                         => '',
                interests =>
                    join( ', ', map { "interest $_" } 1 .. $editor->count_max_interests + 1 ),
                lj_form_auth => $token,
            );
            my $rejected = $request->( POST $url, Content => [%post] );
            is( $rejected->code, 200, 'excess interests return editor after intervening reorder' );

            my ( $retry_fields, $retry_by_dbid ) = _parse_extservice_rows( $rejected->content );
            is( $retry_by_dbid->{$bob_id}{value},
                'bob@other.example', 'redisplay keeps bob value bound to bob account ID' );
            is( $retry_by_dbid->{$alice_id}{value},
                '', 'redisplay keeps cleared value bound to alice account ID' );

            my $retry_token = $form_token->( $rejected->content );
            ok( $retry_token, 'received retry token after Mastodon reorder' ) or return;
            my $accepted = $request->(
                POST $url,
                Content => [
                    %$retry_fields,
                    name                                     => 'Profile owner',
                    LJ__Setting__FindByEmail_opt_findbyemail => 'N',
                    interests                                => 'gardening',
                    lj_form_auth                             => $retry_token,
                ]
            );
            ok( $accepted->is_redirect, 'corrected Mastodon retry redirects' );
            is_deeply(
                $editor->load_profile_accts( force_db => 1 )->{$m_id},
                [ [ $bob_id, 'bob@other.example' ] ],
                'corrected retry deletes only the cleared Mastodon account and preserves bob'
            );
        }

        # 2. Intervening reorder with an invalid Mastodon handle keeps the
        # inline error attached to the edited account's new slot.
        {
            my $editor = temp_user();
            my $url    = 'http://localhost/manage/profile?as=' . $editor->user;
            my $m_id   = $mastodon->{service_id};

            $editor->save_profile_accts(
                { $m_id => [ 'alice@social.example', 'bob@other.example' ] } );
            my $saved = $editor->load_profile_accts( force_db => 1 )->{$m_id};
            my ( $alice_id, $bob_id ) = map { $_->[0] } @$saved;

            my $form  = $request->( GET $url );
            my $token = $form_token->( $form->content );
            my ( $fields, $by_dbid ) = _parse_extservice_rows( $form->content );

            $editor->save_profile_accts( { $m_id => [ [ $alice_id, 'zoe@social.example' ] ] } );

            my $rejected = $request->(
                POST $url,
                Content => [
                    %$fields,
                    name                                     => 'Profile owner',
                    LJ__Setting__FindByEmail_opt_findbyemail => 'N',
                    extservice_val_1                         => 'not-a-handle',
                    interests                                => 'gardening',
                    lj_form_auth                             => $token,
                ]
            );
            is( $rejected->code, 200, 'invalid handle returns editor after intervening reorder' );

            my ( $retry_fields, $retry_by_dbid ) = _parse_extservice_rows( $rejected->content );
            is( $retry_by_dbid->{$bob_id}{value}, 'bob@other.example', 'bob value stays intact' );
            ok( !$retry_by_dbid->{$bob_id}{error}, 'bob field is not marked invalid' );
            is( $retry_by_dbid->{$alice_id}{value},
                'not-a-handle', 'invalid edit follows alice ID' );
            ok( $retry_by_dbid->{$alice_id}{error}, 'field error follows alice ID' );

            my $retry_token = $form_token->( $rejected->content );
            $retry_fields->{"extservice_val_$retry_by_dbid->{$alice_id}{ct}"} =
                'fixed@social.example';
            my $accepted = $request->(
                POST $url,
                Content => [
                    %$retry_fields,
                    name                                     => 'Profile owner',
                    LJ__Setting__FindByEmail_opt_findbyemail => 'N',
                    interests                                => 'gardening',
                    lj_form_auth                             => $retry_token,
                ]
            );
            ok( $accepted->is_redirect, 'fixing the invalid handle after reorder succeeds' );
            is_deeply(
                $editor->load_profile_accts( force_db => 1 )->{$m_id},
                [ [ $bob_id, 'bob@other.example' ], [ $alice_id, 'fixed@social.example' ] ],
                'retry updates only the edited account and preserves bob'
            );
        }

        # 3. Sibling profile service (Patreon) obeys the same identity binding.
        {
            my $editor = temp_user();
            my $url    = 'http://localhost/manage/profile?as=' . $editor->user;
            my $p_id   = $services{patreon}->{service_id};

            $editor->save_profile_accts( { $p_id => [ 'alice', 'bob' ] } );
            my $saved = $editor->load_profile_accts( force_db => 1 )->{$p_id};
            my ( $alice_id, $bob_id ) = map { $_->[0] } @$saved;

            my $form  = $request->( GET $url );
            my $token = $form_token->( $form->content );
            my ( $fields, $by_dbid ) = _parse_extservice_rows( $form->content );

            $editor->save_profile_accts( { $p_id => [ [ $alice_id, 'zoe' ] ] } );

            my $rejected = $request->(
                POST $url,
                Content => [
                    %$fields,
                    name                                     => 'Profile owner',
                    LJ__Setting__FindByEmail_opt_findbyemail => 'N',
                    extservice_val_1                         => '',
                    interests =>
                        join( ', ', map { "interest $_" } 1 .. $editor->count_max_interests + 1 ),
                    lj_form_auth => $token,
                ]
            );
            is( $rejected->code, 200,
                'excess interests return editor for sibling service reorder' );

            my ( $retry_fields, $retry_by_dbid ) = _parse_extservice_rows( $rejected->content );
            is( $retry_by_dbid->{$bob_id}{value},
                'bob', 'sibling service redisplay keeps bob value on bob ID' );
            is( $retry_by_dbid->{$alice_id}{value},
                '', 'sibling service redisplay keeps blank on alice ID' );

            my $retry_token = $form_token->( $rejected->content );
            my $accepted    = $request->(
                POST $url,
                Content => [
                    %$retry_fields,
                    name                                     => 'Profile owner',
                    LJ__Setting__FindByEmail_opt_findbyemail => 'N',
                    interests                                => 'gardening',
                    lj_form_auth                             => $retry_token,
                ]
            );
            ok( $accepted->is_redirect, 'corrected sibling service retry redirects' );
            is_deeply(
                $editor->load_profile_accts( force_db => 1 )->{$p_id},
                [ [ $bob_id, 'bob' ] ],
                'corrected sibling service retry preserves bob and deletes only alice'
            );
        }

        # 4. Intervening delete in another tab does not bind the stale edit to
        # the remaining account.
        {
            my $editor = temp_user();
            my $url    = 'http://localhost/manage/profile?as=' . $editor->user;
            my $m_id   = $mastodon->{service_id};

            $editor->save_profile_accts(
                { $m_id => [ 'alice@social.example', 'bob@other.example' ] } );
            my $saved = $editor->load_profile_accts( force_db => 1 )->{$m_id};
            my ( $alice_id, $bob_id ) = map { $_->[0] } @$saved;

            my $form  = $request->( GET $url );
            my $token = $form_token->( $form->content );
            my ( $fields, $by_dbid ) = _parse_extservice_rows( $form->content );

            $editor->save_profile_accts( { $m_id => [ [ $alice_id, '' ] ] } );

            my $rejected = $request->(
                POST $url,
                Content => [
                    %$fields,
                    name                                     => 'Profile owner',
                    LJ__Setting__FindByEmail_opt_findbyemail => 'N',
                    extservice_val_1                         => '',
                    interests =>
                        join( ', ', map { "interest $_" } 1 .. $editor->count_max_interests + 1 ),
                    lj_form_auth => $token,
                ]
            );
            is( $rejected->code, 200, 'excess interests return editor after intervening delete' );

            my ( $retry_fields, $retry_by_dbid ) = _parse_extservice_rows( $rejected->content );
            ok( !exists $retry_by_dbid->{$alice_id}, 'deleted account is omitted on redisplay' );
            is( $retry_by_dbid->{$bob_id}{value},
                'bob@other.example',
                'remaining account keeps its own value after intervening delete' );

            my $retry_token = $form_token->( $rejected->content );
            my $accepted    = $request->(
                POST $url,
                Content => [
                    %$retry_fields,
                    name                                     => 'Profile owner',
                    LJ__Setting__FindByEmail_opt_findbyemail => 'N',
                    interests                                => 'gardening',
                    lj_form_auth                             => $retry_token,
                ]
            );
            ok( $accepted->is_redirect, 'corrected retry after intervening delete redirects' );
            is_deeply(
                $editor->load_profile_accts( force_db => 1 )->{$m_id},
                [ [ $bob_id, 'bob@other.example' ] ],
                'corrected retry preserves the remaining account'
            );
        }

        # 5. Intervening addition in another tab keeps the new DB row intact
        # and shifts pending new-row input without overwriting it.
        {
            my $editor = temp_user();
            my $url    = 'http://localhost/manage/profile?as=' . $editor->user;
            my $m_id   = $mastodon->{service_id};
            my $p_id   = $services{patreon}->{service_id};

            $editor->save_profile_accts( { $m_id => ['bob@other.example'] } );
            my ($bob_id) =
                map { $_->[0] } @{ $editor->load_profile_accts( force_db => 1 )->{$m_id} };

            my $form  = $request->( GET $url );
            my $token = $form_token->( $form->content );
            my ( $fields, $by_dbid ) = _parse_extservice_rows( $form->content );

            $editor->save_profile_accts( { $m_id => ['alice@social.example'] } );
            my $after_add = $editor->load_profile_accts( force_db => 1 )->{$m_id};
            my ($alice_id) = map { $_->[0] } grep { $_->[0] != $bob_id } @$after_add;

            my $rejected = $request->(
                POST $url,
                Content => [
                    %$fields,
                    name                                     => 'Profile owner',
                    LJ__Setting__FindByEmail_opt_findbyemail => 'N',
                    extservice_site_2                        => $p_id,
                    extservice_val_2                         => 'newpatreon',
                    interests =>
                        join( ', ', map { "interest $_" } 1 .. $editor->count_max_interests + 1 ),
                    lj_form_auth => $token,
                ]
            );
            is( $rejected->code, 200, 'excess interests return editor after intervening add' );

            my ( $retry_fields, $retry_by_dbid ) = _parse_extservice_rows( $rejected->content );
            is( $retry_by_dbid->{$alice_id}{value},
                'alice@social.example',
                'intervening added account keeps its DB value on redisplay' );
            is( $retry_by_dbid->{$bob_id}{value},
                'bob@other.example',
                'existing account keeps its value on redisplay after intervening add' );
            is( $retry_fields->{extservice_site_3},
                $p_id, 'pending new service shifts to the next open slot' );
            is( $retry_fields->{extservice_val_3},
                'newpatreon', 'pending new value stays paired with its service' );

            my $retry_token = $form_token->( $rejected->content );
            my $accepted    = $request->(
                POST $url,
                Content => [
                    %$retry_fields,
                    name                                     => 'Profile owner',
                    LJ__Setting__FindByEmail_opt_findbyemail => 'N',
                    interests                                => 'gardening',
                    lj_form_auth                             => $retry_token,
                ]
            );
            ok( $accepted->is_redirect, 'corrected retry after intervening add redirects' );
            my $final = $editor->load_profile_accts( force_db => 1 );
            is_deeply(
                $final->{$m_id},
                [ [ $alice_id, 'alice@social.example' ], [ $bob_id, 'bob@other.example' ] ],
                'both Mastodon accounts remain intact after retry'
            );
            is_deeply( [ map { $_->[1] } @{ $final->{$p_id} || [] } ],
                ['newpatreon'], 'pending new Patreon account saves after retry' );
        }
    };
};

done_testing();
