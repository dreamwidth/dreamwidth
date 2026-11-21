# t/plack-profile-ban-link.t
#
# Verify that profile bans require a signed-in, CSRF-protected confirmation.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use Plack::Test;
use URI;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Session;
use LJ::Test qw(temp_user temp_comm temp_feed);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $viewer    = temp_user();
my $target    = temp_user();
my $community = temp_comm();
my $feed      = temp_feed();
my $purged    = temp_user();
$purged->update_self( { statusvis => 'X' } );
my $session = LJ::Session->create( $viewer, nolog => 1 ) or die 'Cannot create test session';

my $base         = $LJ::SITEROOT || 'http://localhost';
my $profile      = URI->new_abs( $target->profile_url, $base );
my $confirm      = '/manage/banusers/confirm';
my $action_link  = qr{href="([^"]*/manage/banusers/confirm\?[^"]+)"[^>]*>\s*<img[^>]*>\s*};
my $confirm_form = qr{<form method="post" action="[^"]*/manage/banusers/confirm">(.*?)</form>}s;
my $form_token   = qr/name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;

test_psgi $app, sub {
    my ($app_request) = @_;
    my $guest = $app_request->( GET $profile );
    is( $guest->code, 200, 'guest can see the profile' );
    unlike( $guest->content, $action_link, 'guest has no ban action' );

    my $request = sub {
        my ($http_request) = @_;
        my $domain_cookie = LJ::Session->domain_cookie( $http_request->uri->as_string );
        my $session_cookie =
              $domain_cookie
            ? $domain_cookie . '=' . $session->domsess_cookie_string($domain_cookie)
            : 'ljmastersession=' . $session->master_cookie_string;
        $http_request->header(
            Cookie => "$session_cookie; ljloggedin=" . $session->loggedin_cookie_string );
        return $app_request->($http_request);
    };

    for my $account ( $viewer, $community, $feed, $purged ) {
        my $url      = URI->new_abs( $account->profile_url, $base );
        my $response = $request->( GET $url );
        is( $response->code, $account->is_expunged ? 410 : 200, 'ineligible profile response' );
        unlike( $response->content, $action_link, 'no ban action on ' . $account->journaltype );
    }

    my $page = $request->( GET $profile );
    is( $page->code, 200, 'signed-in viewer can see the profile' );
    like( $page->content, qr/\bLogout\b/i, 'the viewer session is active on the profile' );
    my ($ban_href) = $page->content =~ /$action_link\QBan user\E/;
    ok( $ban_href, 'other user profile links to a ban confirmation' );
    like(
        $page->content,
        qr/$action_link\QBan user\E\s*<\/a>\s*<\/li>\s*<\/ul>/,
        'ban is the last action'
    );
    my $url = URI->new_abs( $ban_href // "$confirm?userid=" . $target->id, $base );
    is( $url->path, $confirm, 'ban action opens the confirmation page' );

    my $guest_confirm = $app_request->( GET $url );
    is(
        URI->new( $guest_confirm->header('Location') // '' )->path,
        '/login',
        'guest cannot open confirmation directly'
    );

    my $ban_form = $request->( GET $url );
    is( $ban_form->code, 200, 'the ban confirmation loads' );
    my ($ban_fields) = $ban_form->content =~ $confirm_form;
    my ($ban_token)  = ( $ban_fields // '' ) =~ $form_token;
    ok( $ban_token, 'confirmation includes a real form token' );
    like( $ban_fields // '', qr/name="action" value="ban"/, 'form submits the ban action' );
    my $target_name = $target->user;
    like( $ban_form->content, qr/\Q$target_name\E/i, 'confirmation names the target' );
    ok( !has_stored_ban( $viewer, $target ), 'GET does not ban' );
    $request->( GET "$url&action=ban" );
    ok( !has_stored_ban( $viewer, $target ), 'GET with a ban action does not ban' );

    my $post = sub {
        my ( $action, $token, $userid ) = @_;
        return $request->(
            POST $url,
            Content => [
                userid       => $userid // $target->id,
                action       => $action,
                lj_form_auth => $token // '',
            ]
        );
    };
    my $invalid = $post->( 'ban', 'invalid' );
    like( $invalid->content, qr/Invalid form submission/i, 'invalid CSRF token is rejected' );
    ok( !has_stored_ban( $viewer, $target ), 'CSRF rejection leaves ban state unchanged' );

    for my $ineligible ( $viewer, $community, $feed, $purged ) {
        $post->( 'ban', $ban_token, $ineligible->id );
        ok( !has_stored_ban( $viewer, $ineligible ), 'POST cannot ban ' . $ineligible->user );
    }

    {
        local $LJ::MAX_BANS = 1;
        my $already_banned = temp_user();
        $viewer->ban_user_multi( $already_banned->id );
        my $limit = $post->( 'ban', $ban_token );
        like( $limit->content, qr/maximum|too many/i, 'ban limit is reported' );
        ok( !has_stored_ban( $viewer, $target ), 'ban limit prevents a new ban' );
        $viewer->unban_user_multi( $already_banned->id );
    }

    my $banned = $post->( 'ban', $ban_token );
    is( $banned->code,               303,        'ban uses post-redirect-get' );
    is( $banned->header('Location'), "$profile", 'ban redirects to target profile' );
    ok( has_stored_ban( $viewer, $target ), 'confirmed POST bans the target' );
    ok( !has_stored_ban( $target, $viewer ), 'only the viewer ban list changes' );

    $post->( 'ban', $ban_token );
    ok( has_stored_ban( $viewer, $target ), 'repeated ban POST does not toggle the ban' );

    $page = $request->( GET $profile );
    my ($unban_href) = $page->content =~ /$action_link\QUnban user\E/;
    ok( $unban_href, 'banned user profile offers Unban user' );
    my $unban_form = $request->( GET( URI->new_abs( $unban_href // $url, $base ) ) );
    my ($unban_fields) = $unban_form->content =~ $confirm_form;
    my ($unban_token)  = ( $unban_fields // '' ) =~ $form_token;
    like( $unban_fields // '', qr/name="action" value="unban"/, 'form submits the unban action' );
    like( $unban_form->content, qr/Unban user/, 'confirmation is for unbanning' );
    ok( has_stored_ban( $viewer, $target ), 'GET does not unban' );
    $request->( GET "$url&action=unban" );
    ok( has_stored_ban( $viewer, $target ), 'GET with an unban action does not unban' );

    local $LJ::MAX_BANS = 1;
    my $unbanned = $post->( 'unban', $unban_token );
    is( $unbanned->code, 303, 'unban redirects even at the ban limit' );
    ok( !has_stored_ban( $viewer, $target ), 'confirmed POST removes the ban' );
    $page = $request->( GET $profile );
    like( $page->content, qr/$action_link\QBan user\E/, 'Ban user is shown again' );
};

done_testing();

sub has_stored_ban {
    my ( $actor, $target ) = @_;
    my $banned = $actor->banned_userids // die 'Cannot read ban list';
    return scalar grep { $_ == $target->id } @$banned;
}
