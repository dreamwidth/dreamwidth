#!/usr/bin/perl
#
# t/plack-settings.t
#
# Characterize settings hub form contracts.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
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
use HTTP::Request::Common;
use HTML::Form;
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
plan skip_all => 'Settings integration requires a development server'
    unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $u     = temp_user();
my $other = temp_user();
$u->set_prop( timeformat_24 => 0 );
$u->set_prop( timezone      => 'Etc/UTC' );
my $session = LJ::Session->create( $u, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'settingsMutationProbe';
test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub {
        my $request = shift;
        $request->header( Cookie => $cookie );
        return $send->($request);
    };
    for my $path ( '/manage/settings/', '/manage/settings/index', '/manage/settings/index.bml' ) {
        my $response = $cb->( GET $path . '?cat=display' );
        is( $response->code, 200, "$path accepts old entry point" );
        like( $response->content, qr/id=['"]settings_form/, 'settings form is available' );
    }
    my $url    = '/manage/settings/?cat=display';
    my $res    = $cb->( GET $url);
    my ($form) = grep { ( $_->attr('id') || '' ) eq 'settings_form' }
        HTML::Form->parse( $res->content, 'http://localhost' . $url );
    ok( $form, 'actual display form parsed' ) or return;
    $form->value( 'DW__Setting__TimeFormat_timeformat', 1 );
    $form->value( 'LJ__Setting__TimeZone_timezone',     'Europe/London' );
    my $req = $form->click;
    $req->uri( 'http://localhost' . $url );
    $res = $cb->($req);
    is( $res->code, 200, 'real display form submitted' );
    like( $res->content, qr/id=['"]settings_form/, 'successful save renders form' );
    like(
        $res->content,
        qr/successfully saved/i,
        'native template resolves the physical settings/index.tt success string'
    );
    unlike(
        $res->content,
        qr{/(?:manage/settings/index|settings/index)[.]tt[.]success},
        'native template never exposes a missing request-language scope key'
    );
    unlike(
        $res->content,
        qr/unblessed|undef error|BML ERROR/,
        'no server exception in save response'
    );
    $res = $cb->( GET $url);
    ($form) = grep { ( $_->attr('id') || '' ) eq 'settings_form' }
        HTML::Form->parse( $res->content, 'http://localhost' . $url );
    is( $form->value('DW__Setting__TimeFormat_timeformat'), 1, 'time format survives fresh GET' );
    is( $form->value('LJ__Setting__TimeZone_timezone'),
        'Europe/London', 'timezone survives fresh GET' );
    my $fresh = LJ::load_userid( $u->id, 1 );
    is( $fresh->prop('timeformat_24'), 1, 'time format persists on forced fresh user' );
    is( $fresh->prop('timezone'), 'Europe/London', 'timezone persists on forced fresh user' );
    my $token = $form->value('lj_form_auth');
    $form->value( 'DW__Setting__TimeFormat_timeformat', 0 );
    $form->value( 'lj_form_auth',                       'invalid' );
    $req = $form->click;
    $req->uri( 'http://localhost' . $url );
    $res = $cb->($req);
    like( $res->content, qr/Invalid form/i, 'invalid token is explained' );
    $res = $cb->( GET $url);
    ($form) = grep { ( $_->attr('id') || '' ) eq 'settings_form' }
        HTML::Form->parse( $res->content, 'http://localhost' . $url );
    is( $form->value('DW__Setting__TimeFormat_timeformat'), 1, 'invalid token does not mutate' );
    $other->set_prop( timeformat_24 => 0 );
    my $other_before = $other->prop('timeformat_24') || 0;
    $res = $cb->(
        POST $url . '&authas=' . $other->user,
        Content => [
            lj_form_auth                         => $token,
            'DW__Setting__TimeFormat_timeformat' => 1
        ]
    );
    unlike( $res->content, qr/id=['"]settings_form/, 'valid-token unauthorized target denied' );
    is( LJ::load_userid( $other->id, 1 )->prop('timeformat_24') || 0,
        $other_before, 'denied target unchanged' );
};

sub settings_cookie {
    my ($user) = @_;
    my $session = LJ::Session->create( $user, nolog => 1 );
    return
          'ljmastersession='
        . $session->master_cookie_string
        . '; ljloggedin='
        . $session->loggedin_cookie_string;
}

sub settings_form {
    my ( $content, $url ) = @_;
    return
        grep { ( $_->attr('id') || '' ) eq 'settings_form' }
        HTML::Form->parse( $content, 'http://localhost' . $url );
}

test_psgi $app, sub {
    my $send     = shift;
    my $anon_url = '/manage/settings/?cat=display';
    my $res      = $send->( GET $anon_url . '&delete_subscription=1' );
    is( $res->code, 200, 'anonymous crafted delete confirmation request renders normally' );
    unlike(
        $res->content,
        qr/(?:Can't call method|Internal Server Error)/,
        'anonymous crafted delete confirmation request cannot dereference an absent user'
    );
    $res = $send->( GET $anon_url );
    is( $res->code, 200, 'anonymous display settings render' );
    my ($form) = settings_form( $res->content, $anon_url );
    ok( $form, 'anonymous display settings expose the cookie-backed form contract' );
    ok( defined $form->value('lj_form_auth'), 'anonymous form retains CSRF contract' );
    ok(
        !defined $form->value('DW__Setting__TimeFormat_timeformat'),
        'anonymous form omits account-backed display settings'
    );
    $form->value( 'DW__Setting__MobileView_val', 1 );
    my $request = $form->click;
    $request->uri( 'http://localhost' . $anon_url );
    $res = $send->($request);
    is( $res->code, 200, 'anonymous MobileView form save returns a rendered response' );
    like( $res->header('Set-Cookie') || '',
        qr/no_mobile=1/, 'anonymous MobileView save sets cookie' );
    my @set_cookies  = $res->headers->header('Set-Cookie');
    my @cookie_pairs = map { /^([^;]+)/ ? $1 : () } @set_cookies;
    diag( 'anonymous MobileView Set-Cookie: ' . join( ' | ', @set_cookies ) );
    $res = $send->( GET $anon_url, Cookie => join( '; ', @cookie_pairs ) );
    ($form) = settings_form( $res->content, $anon_url );
    is( $form->value('DW__Setting__MobileView_val'),
        1, 'anonymous MobileView cookie survives a fresh rendered request' );
    $form->value( 'DW__Setting__MobileView_val', 0 );
    $form->value( 'lj_form_auth',                'invalid' );
    $request = $form->click;
    $request->uri( 'http://localhost' . $anon_url );
    $request->header( Cookie => join( '; ', @cookie_pairs ) );
    $res = $send->($request);
    like( $res->content, qr/Invalid form/i, 'anonymous invalid token is explained' );
    unlike( join( ' | ', $res->headers->header('Set-Cookie') || () ),
        qr/no_mobile=/, 'anonymous invalid token does not update the MobileView cookie' );
    $res = $send->( GET $anon_url, Cookie => join( '; ', @cookie_pairs ) );
    ($form) = settings_form( $res->content, $anon_url );
    is( $form->value('DW__Setting__MobileView_val'),
        1, 'anonymous invalid token does not clear the cookie-backed setting' );
};

test_psgi $app, sub {
    my $send   = shift;
    my $owner  = temp_user();
    my $viewer = temp_user();
    $viewer->grant_priv( 'canview', 'subscriptions' );
    my $inactive =
        $owner->subscribe( event => 'JournalNewEntry', journalid => 0, method => 'Inbox' );
    $inactive->_deactivate;
    my $legacy = $owner->subscribe(
        event   => 'AddedToCircle',
        journal => $owner,
        method  => 'Inbox',
        arg1    => 1
    );
    my $cookie = settings_cookie($owner);
    my $cb     = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };
    my $url    = '/manage/settings/?cat=notifications';
    my $res    = $cb->( GET $url );
    is( $res->code, 200, 'owner notification settings render' );
    my ($form) = settings_form( $res->content, $url );
    ok( $form, 'owner notification settings expose mutation form' ) or return;
    my $token = $form->value('lj_form_auth');
    $res = $cb->( POST $url, Content => [ lj_form_auth => $token, deleteinactive => 1 ] );
    ok( !grep( { $_->id == $inactive->id } LJ::load_userid( $owner->id, 1 )->subscriptions ),
        'deleteinactive removes an inactive subscription through POST' );
    my $legacy_delete_url = $url . '&deletesub_' . $legacy->id . '=1';
    $res = $cb->( GET $legacy_delete_url );
    is( $res->code, 200, 'legacy deletesub URL renders a safe confirmation' );
    ok( grep( { $_->id == $legacy->id } LJ::load_userid( $owner->id, 1 )->subscriptions ),
        'legacy deletesub GET does not mutate the owned subscription' );
    my ($delete_form) = settings_form( $res->content, $legacy_delete_url );
    ok( $delete_form, 'legacy delete confirmation carries a CSRF form' ) or return;
    is( $delete_form->value('delete_subscription_id'),
        $legacy->id, 'confirmation binds the exact owned subscription id' );
    my $delete_token = $delete_form->value('lj_form_auth');
    $delete_form->value( 'lj_form_auth', 'invalid' );
    my $delete_req = $delete_form->click('delete_subscription_confirm');
    $delete_req->uri( 'http://localhost' . $url );
    $res = $cb->($delete_req);
    like( $res->content, qr/Invalid form/i, 'invalid delete confirmation token is explained' );
    ok(
        grep( { $_->id == $legacy->id } LJ::load_userid( $owner->id, 1 )->subscriptions ),
        'invalid delete confirmation token leaves the subscription intact'
    );
    $delete_form->value( 'lj_form_auth', $delete_token );
    $delete_req = $delete_form->click('delete_subscription_confirm');
    $delete_req->uri( 'http://localhost' . $url );
    $res = $cb->($delete_req);
    is( $res->code, 200, 'confirmed legacy deletion returns settings' );
    ok( !grep( { $_->id == $legacy->id } LJ::load_userid( $owner->id, 1 )->subscriptions ),
        'CSRF POST deletes only the confirmed owned subscription' );

    my $viewer_cookie = settings_cookie($viewer);
    my $inspect       = $send->(
        GET '/manage/settings/?cat=notifications&user=' . $owner->user,
        Cookie => $viewer_cookie
    );
    is( $inspect->code, 200, 'privileged notification inspection renders' );
    unlike( $inspect->content, qr/id=['"]settings_form/,
        'privileged inspection exposes no mutation form' );

    # A valid CSRF token isn't tied to the page that issued it, only the
    # session, so a token from an unrelated page still isolates this
    # privilege-escalation guard from the generic CSRF guard proven above.
    my $protected = LJ::load_userid( $owner->id, 1 )
        ->subscribe( event => 'JournalNewEntry', journalid => 0, method => 'Inbox' );
    $protected->_deactivate;
    my $viewer_display = $send->( GET '/manage/settings/?cat=display', Cookie => $viewer_cookie );
    my ($viewer_form) = settings_form( $viewer_display->content, '/manage/settings/?cat=display' );
    my $forged_res = $send->(
        POST '/manage/settings/?cat=notifications&user=' . $owner->user,
        Cookie  => $viewer_cookie,
        Content => [ lj_form_auth => $viewer_form->value('lj_form_auth'), deleteinactive => 1 ]
    );

    # A valid token proves check_form_auth passed, so this content is
    # specifically the inspection guard rejecting the POST, not an
    # incidental CSRF failure.
    like(
        $forged_res->content,
        qr/couldn.t be authenticated as the specified account/,
        'the forged POST is rejected by the inspection guard, not a CSRF failure'
    );
    ok(
        grep( { $_->id == $protected->id } LJ::load_userid( $owner->id, 1 )->subscriptions ),
        'a forged deleteinactive POST from a privileged inspector cannot mutate the owner'
    );
};

done_testing;
