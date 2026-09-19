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
use LJ::Test qw(temp_user temp_comm temp_feed with_fake_memcache);
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
    sub host { 'localhost' }

    sub header_in {
              $_[1] eq 'X-LJ-Auth'     ? ( $_[0]->{cookie_auth} ? 'cookie' : '' )
            : $_[1] eq 'Authorization' ? ( $_[0]->{authorization} // '' )
            :                            '';
    }
    sub get_remote_ip { '127.0.0.1' }
    sub note          { undef }
    sub cookie        { $_[0]->{cookies}{ $_[1] } }
    sub delete_cookie { }
    sub redirect      { $_[1] }
    sub did_post      { $_[0]->{did_post} || 0 }
    sub post_args     { $_[0]->{post} || {} }
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

{
    local *DW::Controller::Login::controller = sub { ( 1, { r => $request } ) };
    local *DW::Auth::Login::complete         = sub { 1 };
    my @metrics;
    local *DW::Stats::increment = sub { push @metrics, [@_] };
    $request->{cookies}{ljmfapending} = DW::Auth::Login->begin($u);
    local $request->{did_post} = 1;
    for my $bindip ( '', '127.0.0.1' ) {
        local *DW::Auth::Login::verify = sub { ( $u, { bindip => $bindip, exptype => 'long' } ) };
        DW::Controller::Login::login_2fa_handler();
        is_deeply(
            pop @metrics,
            [
                'dw.action.session.login_ok', 1,
                [ 'bindip:' . ( $bindip ? 'yes' : 'no' ), 'exptype:long' ]
            ],
            'MFA success records login metric with original session options'
        );
    }
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
ok(
    !DW::Auth::TOTP->mark_session( $u, $session ),
    'Issuing proof requires the factor actually verified'
);
DW::Auth::TOTP->mark_session( $u, $session, DW::Auth::TOTP->_factor_state($u)->{factor} );
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
    local *LJ::User::publish_login_session = sub { 1 };
    local *LJ::get_remote                  = sub { undef };
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
    {
        local *LJ::User::kill_all_sessions = sub { 0 };
        eval { DW::Auth::TOTP->enable( $cached_user, $cache_secret ) };
        like( $@, qr/Unable to revoke/, 'Revocation failure prevents successful enrollment' );
    }
    ok( !DW::Auth::TOTP->is_enabled($cached_user), 'Failed enrollment rolls factor back' );
    ok( $plain->valid, 'Failed enrollment restores ordinary session validation' );
    DW::Auth::TOTP->enable( $cached_user, $cache_secret );
    ok( !$plain->valid, 'Enabling factor immediately invalidates cached password-only session' );
    my $proven = LJ::Session->create( $cached_user, exptype => 'long' );
    DW::Auth::TOTP->mark_session( $cached_user, $proven,
        DW::Auth::TOTP->_factor_state($cached_user)->{factor} );
    ok( $proven->valid, 'Warm MFA session cache' );
    {
        local *LJ::get_db_writer = sub { die 'Unexpected writer access' };
        ok( $proven->valid, 'Warm MFA session needs no writer query' );
    }

    # Simulate a worker exiting after publishing the marker and rolling back.
    $dbh->begin_work;
    $dbh->do( 'UPDATE password2 SET totp_secret = NULL WHERE userid = ?', undef, $cached_user->id );
    DW::Auth::TOTP->_factor_changing($cached_user);
    $dbh->rollback;
    ok( $proven->valid, 'Abandoned factor-change marker recovers immediately from database' );
    ok( !$plain->valid, 'Marker recovery retains MFA enforcement' );
    my @failure_codes = DW::Auth::TOTP->get_recovery_codes($cached_user);
    {
        local *LJ::User::kill_all_sessions = sub { 0 };
        eval { DW::Auth::TOTP->disable( $cached_user, 'cache-test-password', $failure_codes[0] ) };
        like( $@, qr/Unable to revoke/, 'Revocation failure prevents successful disable' );
    }
    ok( DW::Auth::TOTP->is_enabled($cached_user), 'Revocation failure retains factor' );
    ok( !$plain->valid, 'Revocation failure cannot authorize old password-only session' );
    ok( $proven->valid, 'Existing verified session remains usable after failed disable' );
    my @remaining_codes = DW::Auth::TOTP->get_recovery_codes($cached_user);
    ok( scalar( grep { $_ eq $failure_codes[0] } @remaining_codes ),
        'Failed disable does not burn recovery code' );
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

with_fake_memcache {
    my $racing_user = temp_user();
    $racing_user->set_password('race-password');
    DW::Auth::TOTP->enable( $racing_user, DW::Auth::TOTP->generate_secret );
    my @race_codes = DW::Auth::TOTP->get_recovery_codes($racing_user);
    my $challenge  = DW::Auth::Login->begin($racing_user);
    my ( $verified, $completion ) = DW::Auth::Login->verify( $challenge, $race_codes[0] );
    ok( $verified, 'Race fixture verifies the original factor' );
    local *LJ::get_remote = sub { undef };
    {
        my $get_writer = \&LJ::get_db_writer;
        my $raced;
        local *LJ::get_db_writer = sub {
            my $writer = $get_writer->(@_);
            unless ( $raced++ ) {
                DW::Auth::TOTP->disable( $racing_user, 'race-password', $race_codes[1] );
                DW::Auth::TOTP->enable( $racing_user, DW::Auth::TOTP->generate_secret );
            }
            return $writer;
        };
        ok(
            !DW::Auth::Login->complete( $racing_user, %$completion, mfa_verified => 1 ),
            'Factor replacement before completion lock cannot upgrade old verification'
        );
        is( scalar LJ::Session->active_sessions($racing_user),
            0, 'Racing login creates no replacement-factor session' );
    }
    my $source = LJ::Session->create( $racing_user, exptype => 'long' );
    DW::Auth::TOTP->mark_session( $racing_user, $source,
        DW::Auth::TOTP->_factor_state($racing_user)->{factor} );
    my $destination = LJ::Session->create( $racing_user, exptype => 'long' );
    ok( DW::Auth::TOTP->copy_session_proof( $racing_user, $source, $destination ),
        'Replacement session inherits a valid source proof' );
    ok( $destination->valid, 'Inherited current-factor proof validates' );
    {
        local *LJ::get_remote = sub { $racing_user };
        local $request->{cookie_auth} = 1;
        my $error;
        my $result = LJ::Protocol::sessiongenerate(
            { username => $racing_user->user, auth_method => 'cookie', expiration => 'long' },
            \$error, {} );
        ok( $result && $result->{ljsession}, 'Verified cookie can request a replacement session' );
        ok( $racing_user->session->valid,    'Cookie replacement carries the original MFA proof' );
    }
};

with_fake_memcache {
    my $racing_user = temp_user();
    $racing_user->set_password('race-password');
    my $source = LJ::Session->create( $racing_user, exptype => 'long' );
    ok( $source->valid, 'Cookie session initially needs no second factor' );
    local *LJ::get_remote             = sub { $racing_user };
    local *LJ::Protocol::authenticate = sub { $_[2]->{u} = $racing_user; 1 };
    my $writer = \&LJ::get_db_writer;
    my $raced;
    local *LJ::get_db_writer = sub {
        my $dbh = $writer->(@_);
        DW::Auth::TOTP->enable( $racing_user, DW::Auth::TOTP->generate_secret ) unless $raced++;
        return $dbh;
    };
    my $error;
    ok(
        !LJ::Protocol::sessiongenerate(
            { auth_method => 'cookie', expiration => 'long' },
            \$error, {}
        ),
        'Concurrent enrollment prevents cookie exchange from minting MFA proof'
    );
    ok( !$racing_user->session->valid, 'Password-only source cannot become an MFA session' );
};

for my $account ( $u, temp_comm(), temp_feed() ) {
    my $key     = DW::API::Key->new_for_user($account);
    my $allowed = $account->is_person ? 1 : 0;
    is( DW::API::Key->authenticate( $account, $key->hash ) ? 1 : 0,
        $allowed, 'API key authentication requires a personal account' );
    my $error;
    is(
        LJ::Protocol::authenticate( { username => $account->user, password => $key->hash },
            \$error, {} ) ? 1 : 0,
        $allowed,
        'Clear protocol key authentication requires a personal account'
    );
    my $challenge = DW::Auth::Challenge->generate(300);
    my $response  = Digest::MD5::md5_hex( $challenge . Digest::MD5::md5_hex( $key->hash ) );
    is( LJ::Protocol::check_login( $account, $challenge, $response, undef, {} ) ? 1 : 0,
        $allowed, 'Challenge API-key authentication requires a personal account' );
    require POSIX;
    my $created = POSIX::strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime );
    my $nonce   = 'personal-key-policy-' . $account->id;
    my $digest  = Digest::SHA1::sha1_base64( $nonce . $created . $key->hash );
    my ($wsse) =
        DW::Auth::_auth_wsse( 'UsernameToken Username="'
            . $account->user
            . '", PasswordDigest="'
            . $digest
            . '", Nonce="'
            . $nonce
            . '", Created="'
            . $created
            . '"' );
    is( $wsse ? 1 : 0, $allowed, 'WSSE API-key authentication requires a personal account' );
}
with_fake_memcache {
    my $ordinary = temp_user();
    my $source   = LJ::Session->create( $ordinary, exptype => 'long' );
    ok( $source->valid, 'Ordinary replacement source warms factor state' );
    local *LJ::get_remote = sub { $ordinary };
    local $request->{cookie_auth} = 1;
    my $destination = LJ::Session->create( $ordinary, exptype => 'long' );
    $ordinary->{_session} = $source;

    # Counter allocation already uses the global database; isolate the added MFA work.
    local *LJ::Session::create            = sub { $ordinary->{_session} = $destination };
    local *DW::Auth::TOTP::_session_proof = sub { die 'Unexpected MFA proof lookup' };
    my $error;
    my $result = LJ::Protocol::sessiongenerate(
        { username => $ordinary->user, auth_method => 'cookie', expiration => 'long' },
        \$error, {} );
    ok( $result && $result->{ljsession}, 'Ordinary cookie replacement needs no MFA proof lookup' );
    ok( $ordinary->session->valid,       'Ordinary replacement remains valid' );
};
{
    my $account = temp_user();
    $account->set_password('old-login-password');
    ok( $account->check_password('old-login-password'), 'Initial password verification succeeds' );
    $account->set_password('new-login-password');
    my $published = 0;
    local *LJ::User::publish_login_session = sub { ++$published; 1 };
    ok(
        !DW::Auth::Login->complete( $account, password => 'old-login-password' ),
        'Password change before completion lock invalidates stale login'
    );
    is( $published, 0, 'Stale login never publishes browser state' );
    ok( DW::Auth::Login->complete( $account, password => 'new-login-password' ),
        'Current password completes ordinary login' );
    DW::Auth::TOTP->enable( $account, DW::Auth::TOTP->generate_secret );
    ok( !DW::Auth::Login->begin( $account, password => 'old-login-password' ),
        'Stale password cannot create an MFA challenge' );
    my $challenge = DW::Auth::Login->begin( $account, password => 'new-login-password' );
    my ( $pending, $options ) = DW::Auth::Login->pending($challenge);
    ok( $pending && !exists $options->{password}, 'MFA challenge stores no plaintext password' );
}
{
    my $account = temp_user();
    LJ::Session->create( $account, exptype => 'long' );
    local *LJ::get_remote         = sub { $account };
    local $request->{cookie_auth} = 1;
    local *LJ::Session::create    = sub { undef };
    local *DW::Auth::TOTP::copy_session_proof =
        sub { die 'Unexpected proof copy after failed creation' };
    my $error;
    my $result = LJ::Protocol::sessiongenerate(
        { username => $account->user, auth_method => 'cookie', expiration => 'long' },
        \$error, {} );
    ok( !$result, 'Failed session creation returns a protocol failure' );
    is( $error, 502, 'Failed session creation returns database-unavailable error' );
}

with_fake_memcache {
    my $account = temp_user();
    $account->set_password('disable-race-password');
    DW::Auth::TOTP->enable( $account, DW::Auth::TOTP->generate_secret );
    my @codes  = DW::Auth::TOTP->get_recovery_codes($account);
    my $source = LJ::Session->create( $account, exptype => 'long' );
    DW::Auth::TOTP->mark_session( $account, $source,
        DW::Auth::TOTP->_factor_state($account)->{factor} );
    local *LJ::get_remote             = sub { $account };
    local *LJ::Protocol::authenticate = sub { $_[2]->{u} = $account; 1 };
    my $get_writer = \&LJ::get_db_writer;
    my $raced;
    local *LJ::get_db_writer = sub {
        my $dbh = $get_writer->(@_);
        DW::Auth::TOTP->disable( $account, 'disable-race-password', $codes[0] ) unless $raced++;
        return $dbh;
    };
    my $error;
    ok(
        !LJ::Protocol::sessiongenerate(
            { auth_method => 'cookie', expiration => 'long' },
            \$error, {}
        ),
        'Disable between authentication and replacement cannot revive revoked cookie'
    );
    is( $error, 300, 'Revoked source returns authentication failure' );
    is( scalar LJ::Session->active_sessions($account), 0, 'Disable race creates no sessions' );
};
for my $throws ( 0, 1 ) {
    my $account = temp_user();
    my $source  = LJ::Session->create( $account, exptype => 'long' );
    local *LJ::get_remote = sub { $account };
    local $request->{cookie_auth} = 1;
    my $created;
    my $create = \&LJ::Session::create;
    local *LJ::Session::create = sub {
        ok( !LJ::get_db_writer()->{AutoCommit}, 'Replacement is created under account lock' );
        $created = $create->(@_);
    };
    local *DW::Auth::TOTP::copy_session_proof = sub {
        die 'Proof unavailable' if $throws;
        return;
    };
    my $error;
    ok(
        !LJ::Protocol::sessiongenerate(
            { username => $account->user, auth_method => 'cookie', expiration => 'long' },
            \$error, {}
        ),
        'Proof-copy failure returns protocol error'
    );
    is( $error,            $throws ? 502 : 300, 'Proof failure reports appropriate error' );
    is( $account->session, $source,             'Proof failure restores source session pointer' );
    ok( !LJ::Session->instance( $account, $created->id ), 'Proof failure deletes replacement' );
    ok( LJ::Session->instance( $account, $source->id )->valid, 'Source session remains usable' );
}
done_testing();
