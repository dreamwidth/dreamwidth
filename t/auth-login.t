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
use LJ::Test qw(temp_user);
use DW::Auth::Login;
use DW::Auth::TOTP;
use DW::API::Key;
use LJ::Protocol;
use DW::Auth;
use MIME::Base64 qw(encode_base64);
use DW::Controller::Entry;
use Digest::SHA qw(sha256_hex);

{

    package LoginTestRequest;
    sub host          { 'localhost' }
    sub header_in     { $_[1] eq 'Authorization' ? ( $_[0]->{authorization} // '' ) : '' }
    sub get_remote_ip { '127.0.0.1' }
    sub note          { undef }
    sub cookie        { undef }
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
my ($verified) = DW::Auth::Login->verify( $token, $recovery[0] );
is( $verified->id, $u->id, 'Recovery code completes challenge' );
ok( !DW::Auth::Login->pending($token), 'Successful challenge consumed' );
ok( !DW::Auth::TOTP->verify( $u, $recovery[0] ), 'Recovery code cannot be reused' );

$token = DW::Auth::Login->begin($u);
for ( 1 .. 5 ) { ok( !DW::Auth::Login->verify( $token, 'invalid' ), 'Bad code fails' ); }
ok( !DW::Auth::Login->pending($token), 'Five attempts exhaust challenge' );
ok(
    !DW::Auth::Login->verify( $token, $recovery[1] ),
    'Exhausted challenge cannot consume valid code'
);
ok( DW::Auth::TOTP->verify( $u, $recovery[1] ), 'Unused recovery code remains valid' );

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
done_testing();
