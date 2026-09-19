#!/usr/bin/perl
#
# t/auth-login.t
#
# Regression tests for MFA challenges and alternate authentication paths.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
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
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm with_fake_memcache);
use DW::Auth::Login;
use DW::Auth::TOTP;
use DW::API::Key;
use LJ::Protocol;
use DW::Auth;
use MIME::Base64 qw(encode_base64);
use DW::Controller::Entry;
use Digest::SHA qw(sha256_hex);
use DW::Controller::Login;

{

    package LoginTestRequest;
    sub host          { 'localhost' }
    sub header_in     { $_[1] eq 'Authorization' ? ( $_[0]->{authorization} // '' ) : '' }
    sub get_remote_ip { '127.0.0.1' }
    sub note          { undef }
    sub cookie        { $_[0]->{cookies}{ $_[1] } }
    sub delete_cookie { }
    sub redirect      { $_[1] }
    sub did_post      { 0 }
}
my $request = bless {}, 'LoginTestRequest';
no warnings 'redefine';

my $u = temp_user();
$u->set_password('test-password');
my $secret = DW::Auth::TOTP->generate_secret;
DW::Auth::TOTP->enable( $u, $secret );
my @recovery = DW::Auth::TOTP->get_recovery_codes($u);
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'mfa-browser-one';
my $dbh = LJ::get_db_writer();

my $token = DW::Auth::Login->begin( $u, returnto => '/entry/new', store_only => 1 );
my ( $pending, $opts ) = DW::Auth::Login->pending($token);
is( $pending->id, $u->id, 'Pending challenge belongs to account' );
ok( $opts->{store_only},                      'Store-only intent survives challenge' );
ok( !DW::Auth::Login->pending('not-a-token'), 'Malformed token rejected' );
{
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'another-browser';
    ok( !DW::Auth::Login->pending($token), 'Challenge bound to browser' );
}
my $restart = DW::Auth::Login->restart_token(
    returnto   => '/entry/new?draft=1',
    store_only => 1,
    adding     => 1
);
my $restart_url =
    "$LJ::SITEROOT/login?switch=1&store_only=1&returnto=" . LJ::eurl('/entry/new?draft=1');
is( DW::Auth::Login->restart_url($restart), $restart_url,
    'Restart preserves validated navigation' );
{
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'another-browser';
    is( DW::Auth::Login->restart_url($restart), "$LJ::SITEROOT/login", 'Restart is browser-bound' );
}
is( DW::Auth::Login->restart_url('bad-cookie'),
    "$LJ::SITEROOT/login", 'Malformed restart rejected' );
my $tampered = $restart;
$tampered =~ s/:3600:/:7200:/;
is( DW::Auth::Login->restart_url($tampered), "$LJ::SITEROOT/login",
    'Tampered navigation rejected' );

my ($verified) = DW::Auth::Login->verify( $token, $recovery[0] );
is( $verified->id, $u->id, 'Recovery code completes challenge' );
ok( !DW::Auth::Login->pending($token), 'Successful challenge consumed' );
ok( !DW::Auth::TOTP->verify( $u, $recovery[0] ), 'Recovery code cannot be reused' );

# Interleave two requests after both could have read the same pending challenge.
# The loser must recheck under the account lock before consuming its own code.
{
    my $race_token     = DW::Auth::Login->begin($u);
    my $pending_method = \&DW::Auth::Login::pending;
    my $first          = 1;
    local *DW::Auth::Login::pending = sub {
        my @pending = $pending_method->(@_);
        if ($first) {
            $first = 0;
            my ($winner) = DW::Auth::Login->verify( $race_token, $recovery[4] );
            ok( $winner, 'First concurrent submission succeeds' );
        }
        return @pending;
    };
    ok(
        !DW::Auth::Login->verify( $race_token, $recovery[5] ),
        'Stale submission cannot reuse challenge'
    );
    ok(
        DW::Auth::TOTP->verify( $u, $recovery[5] ),
        'Losing submission leaves its recovery code unused'
    );
}

{
    my $failed_token  = DW::Auth::Login->begin($u);
    my $verify_factor = \&DW::Auth::TOTP::verify;
    {
        local *DW::Auth::TOTP::verify = sub {
            $verify_factor->(@_);
            die "Injected factor failure\n";
        };
        eval { DW::Auth::Login->verify( $failed_token, $recovery[6] ) };
        like( $@, qr/Injected factor failure/, 'Challenge verification reports storage failure' );
    }
    ok( DW::Auth::Login->pending($failed_token), 'Failed transaction leaves challenge available' );
    ok( DW::Auth::TOTP->verify( $u, $recovery[6] ), 'Failed transaction restores consumed code' );
}

$token = DW::Auth::Login->begin($u);
for ( 1 .. 5 ) { ok( !DW::Auth::Login->verify( $token, 'invalid' ), 'Bad code fails' ); }
ok( !DW::Auth::Login->pending($token), 'Five attempts exhaust challenge' );
ok(
    !DW::Auth::Login->verify( $token, $recovery[1] ),
    'Exhausted challenge cannot consume valid code'
);
ok( DW::Auth::TOTP->verify( $u, $recovery[1] ), 'Unused recovery code remains valid' );

{
    local *DW::Controller::Login::controller = sub { ( 1, { r => $request } ) };
    local *DW::Template::render_template     = sub { $_[2] };
    $request->{cookies} = { ljmfapending => $token, ljmfarestart => $restart };
    is( DW::Controller::Login::login_2fa_handler(),
        $restart_url, 'Exhausted challenge redirects with store-only and draft destination' );
    $request->{cookies}{ljmfapending} = DW::Auth::Login->begin($u);
    is( DW::Controller::Login::login_2fa_handler()->{restart_url},
        $restart_url, 'Back link uses the same validated restart URL' );
    $dbh->do( 'UPDATE login_challenges SET expires = 0 WHERE token = ?',
        undef, sha256_hex( $request->{cookies}{ljmfapending} ) );
    is( DW::Controller::Login::login_2fa_handler(),
        $restart_url, 'Expired challenge preserves comment navigation' );
}

$token = DW::Auth::Login->begin($u);
$dbh->do( 'UPDATE login_challenges SET expires = 0 WHERE token = ?', undef, sha256_hex($token) );
ok( !DW::Auth::Login->pending($token), 'Expired challenge rejected' );
$token = DW::Auth::Login->begin($u);
$u->set_password('new-password');
ok( DW::Auth::TOTP->is_enabled($u),    'Password reset preserves second factor' );
ok( !DW::Auth::Login->pending($token), 'Password reset invalidates pending challenge' );

local *DW::Request::get = sub { $request };
my $session = LJ::Session->create( $u, exptype => 'long' );
ok( !$session->valid, 'Password-only/legacy session rejected for MFA account' );
DW::Auth::TOTP->mark_session( $u, $session );
ok( $session->valid,                'Session with server-side MFA proof accepted' );
ok( !DW::Auth::Login->complete($u), 'Completion refuses MFA without verification' );
$session->set_exptype('long');
my ($proof_expiry) =
    $dbh->selectrow_array( 'SELECT expires FROM mfa_sessions WHERE userid = ? AND sessid = ?',
    undef, $u->id, $session->id );
is( $proof_expiry, $session->expiration_time, 'MFA proof follows session renewal' );
$token = DW::Auth::Login->begin($u);
$u->update_self( { statusvis => 'L' } );
ok( !DW::Auth::Login->pending($token), 'Locking account invalidates pending login' );
$u->update_self( { statusvis => 'V' } );
is( DW::Auth::Login->return_url('/entry/new'), '/entry/new', 'Relative return URL allowed' );
ok( !DW::Auth::Login->return_url('//evil.example/'),       'Protocol-relative redirect rejected' );
ok( !DW::Auth::Login->return_url('https://evil.example/'), 'External redirect rejected' );
ok( !DW::Auth::Login->return_url("/\\evil.example/"),      'Backslash redirect rejected' );
ok( !DW::Auth::Login->return_url("/ok\r\nLocation: bad"),  'Header injection rejected' );
my @codes = DW::Auth::TOTP->_get_codes($u);
ok( DW::Auth::TOTP->verify( $u, $codes[1] ), 'Current TOTP accepted once' );
ok( !DW::Auth::TOTP->verify( $u, $codes[1] ), 'TOTP replay rejected' );
ok( !DW::Auth::TOTP->verify( $u, $codes[0] ), 'Earlier time step rejected after newer code' );

my $key = DW::API::Key->new_for_user($u);
$request->{authorization} = 'Basic ' . encode_base64( $u->user . ':new-password', '' );
my ($basic) = DW::Auth::_auth_basic();
ok( !$basic, 'HTTP Basic rejects account password' );
$request->{authorization} = 'Basic ' . encode_base64( $u->user . ':' . $key->hash, '' );
($basic) = DW::Auth::_auth_basic();
ok( $basic && $basic->equals($u), 'HTTP Basic accepts API key for MFA account' );

ok(
    !DW::API::Key->authenticate( $u, 'new-password' ),
    'API authentication rejects account password'
);
ok( DW::API::Key->authenticate( $u, $key->hash ), 'API key accepted for MFA account' );
my ( $err, $flags );
$flags = {};
ok(
    !LJ::Protocol::authenticate(
        { username => $u->user, password => 'new-password' },
        \$err, $flags
    ),
    'Protocol rejects password'
);
$flags = {};
ok( LJ::Protocol::authenticate( { username => $u->user, password => $key->hash }, \$err, $flags ),
    'Protocol accepts API key' );
$flags = {};
ok(
    !LJ::Protocol::sessiongenerate(
        { username => $u->user, password => $key->hash },
        \$err, $flags
    ),
    'API key cannot mint browser session'
);
my %flat_response;
is( LJ::sessiongenerate( { user => $u->user, password => $key->hash }, \%flat_response, {} ),
    0, 'Legacy flat sessiongenerate returns failure' );
is( $flat_response{success}, 'FAIL', 'Legacy wrapper preserves FAIL response' );
ok( !exists $flat_response{ljsession}, 'Legacy wrapper never returns a browser session' );

$key->delete($u);
ok( !DW::API::Key->authenticate( $u, $key->hash ), 'Revoked API key rejected' );

my %posting_flags;
my %auth =
    DW::Controller::Entry::_auth( \%posting_flags,
    { username => $u->user, password => 'new-password' },
    undef, 'http://example.com' );
ok( !$posting_flags{noauth}, 'Entry editor rejects inline password authentication' );

$token = DW::Auth::Login->begin($u);
$dbh->do( 'UPDATE login_challenges SET attempts = 20 WHERE token = ?', undef, sha256_hex($token) );
my $fresh_token = DW::Auth::Login->begin($u);
ok(
    !DW::Auth::Login->verify( $fresh_token, $recovery[3] ),
    'Fresh challenge cannot bypass account attempt budget'
);
ok( DW::Auth::TOTP->verify( $u, $recovery[3] ), 'Rate limiting does not consume a recovery code' );

ok( !DW::Auth::TOTP->disable( $u, 'new-password', 'invalid' ),
    'Password alone cannot remove second factor' );
ok(
    DW::Auth::TOTP->disable( $u, 'new-password', $recovery[2] ),
    'Password and recovery code disable second factor'
);
ok( !DW::Auth::TOTP->is_enabled($u), 'Factor removed explicitly' );
is( scalar DW::Auth::TOTP->get_recovery_codes($u), 0, 'Recovery codes revoked on disable' );
{
    my $community = temp_comm();
    local $LJ::DISABLED{'community-logins'} = 0;
    ok( DW::Auth::Login->allowed($community), 'Enabled community logins can complete' );
    ok( !DW::Auth::Login->begin($community),  'Communities cannot start personal MFA challenges' );
    local *LJ::User::make_login_session = sub { 1 };
    local *LJ::get_remote               = sub { undef };
    ok( DW::Auth::Login->complete($community), 'Normal community completion succeeds' );
    $LJ::DISABLED{'community-logins'} = 1;
    ok( !DW::Auth::Login->complete($community), 'Disabled community logins remain rejected' );
}

with_fake_memcache {
    my $cached_user = temp_user();
    $cached_user->set_password('cache-test-password');
    my $plain = LJ::Session->create( $cached_user, exptype => 'long' );
    ok( $plain->valid, 'Warm ordinary session cache' );
    {
        local *LJ::get_db_writer = sub { die 'Unexpected writer access' };
        ok( $plain->valid, 'Warm ordinary session needs no writer query' );
    }
    my $cache_secret = DW::Auth::TOTP->generate_secret;
    DW::Auth::TOTP->enable( $cached_user, $cache_secret );
    ok( !$plain->valid, 'Enabling factor immediately invalidates cached password-only session' );
    my $proven = LJ::Session->create( $cached_user, exptype => 'long' );
    DW::Auth::TOTP->mark_session( $cached_user, $proven );
    ok( $proven->valid, 'Warm MFA session cache' );
    {
        local *LJ::get_db_writer = sub { die 'Unexpected writer access' };
        ok( $proven->valid, 'Warm MFA session needs no writer query' );
    }
    $proven->destroy;
    ok( !DW::Auth::TOTP->session_verified($proven), 'Destroyed session loses cached MFA proof' );
    my @cache_codes = DW::Auth::TOTP->get_recovery_codes($cached_user);
    ok( DW::Auth::TOTP->disable( $cached_user, 'cache-test-password', $cache_codes[0] ),
        'Disable factor with cached state' );
    my $new_plain = LJ::Session->create( $cached_user, exptype => 'long' );
    ok( $new_plain->valid, 'Disabling factor refreshes cached state' );
    DW::Auth::TOTP->enable( $cached_user, $cache_secret );
    ok( !$new_plain->valid, 'Reenabling same secret invalidates ordinary session' );
    ok( !DW::Auth::TOTP->session_verified($proven), 'Reenrollment cannot reuse old factor proof' );
};

done_testing();
