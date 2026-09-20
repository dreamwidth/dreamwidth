#!/usr/bin/perl
#
# t/auth-2fa-compat.t
#
# Compatibility and protected-account authentication regression tests.
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
use LJ::Test qw(temp_user with_fake_memcache);
use DW::Auth;
use DW::Auth::Login;
use DW::Auth::TOTP;
use DW::Auth::Challenge;
use DW::Controller::Talk;
use DW::Controller::Entry;
use DW::Controller::Settings;
use DW::Controller::Admin::UserViews;
use DW::Controller::Mobile::Login;
use POSIX ();
use DW::API::Key;
use LJ::Protocol;
use Digest::MD5 qw(md5_hex);
use Digest::SHA qw(sha256_hex);
use Digest::SHA1 ();
use MIME::Base64 qw(encode_base64);

{

    package CompatibilityRequest;
    sub post_args { $_[0]->{post} || {} }
    sub did_post  { 1 }
    sub get_args  { {} }
    sub redirect  { $_[1] }

    sub host           { 'localhost' }
    sub get_remote_ip  { '127.0.0.1' }
    sub header_in      { $_[0]->{headers}{ $_[1] } // '' }
    sub header_out     { }
    sub header_out_add { }
    sub note           { undef }
    sub cookie         { $_[0]->{cookies}{ $_[1] } }
    sub add_cookie     { my ( $self, %args ) = @_; $self->{cookies}{ $args{name} } = $args{value} }

    sub err_header_out {
        my ( $self, $name, $values ) = @_;
        $self->{response} = $values if defined $values;
        return @{ $self->{response} || [] };
    }
}
my $request = bless { headers => {}, cookies => {} }, 'CompatibilityRequest';
my $remote;
no warnings 'redefine';
local *DW::Request::get             = sub { $request };
local *LJ::get_remote               = sub { $remote };
local *LJ::User::set_remote         = sub { $remote = $_[1] };
local *LJ::UniqCookie::current_uniq = sub { 'compat-browser' };
local *LJ::check_referer            = sub { 1 };
local $LJ::ADMIN_EMAIL              = 'test@example.invalid';

sub protocol_auth {
    my ( $u, %args ) = @_;
    my ( $error, %flags );
    my $ok = LJ::Protocol::authenticate( { username => $u->user, %args }, \$error, \%flags );
    return $ok;
}

sub basic_auth {
    my ( $u, $credential ) = @_;
    local $request->{headers}{Authorization} =
        'Basic ' . encode_base64( $u->user . ':' . $credential, '' );
    return ( DW::Auth::_auth_basic() )[0];
}

sub exchange {
    my ( $u, %args ) = @_;
    my $error;
    return LJ::Protocol::sessiongenerate( { username => $u->user, expiration => 'long', %args },
        \$error, {} );
}

for my $protected ( 0, 1 ) {
    my $u = temp_user();
    $u->set_password('compat-password');
    $u->update_self( { status => 'A' } );
    my $key = DW::API::Key->new_for_user($u);
    my $old = LJ::Session->create( $u, exptype => 'long' );
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret ) if $protected;
    my $label = $protected ? 'Protected' : 'Ordinary';
    is(
        protocol_auth( $u, password => 'compat-password' ) ? 1 : 0,
        $protected ? 0 : 1,
        "$label protocol password behavior"
    );
    ok( protocol_auth( $u, password => $key->hash ), "$label protocol API key remains accepted" );
    ok( protocol_auth( $u, hpassword => md5_hex( $key->hash ) ),
        "$label hashed API key remains accepted" );
    is(
        basic_auth( $u, 'compat-password' ) ? 1 : 0,
        $protected ? 0 : 1,
        "$label Basic password behavior"
    );
    ok( basic_auth( $u, $key->hash ), 'Protected Basic accepts replacement API key' ) if $protected;
    is(
        exchange( $u, password => 'compat-password' ) ? 1 : 0,
        $protected ? 0 : 1,
        "$label password session exchange behavior"
    );
    ok( exchange( $u, password => $key->hash ), "$label existing API-key session exchange works" );
    ok( $u->session->valid, "$label API session is usable" );
    my $challenge = DW::Auth::Challenge->generate;
    ok(
        exchange(
            $u,
            auth_method    => 'challenge',
            auth_challenge => $challenge,
            auth_response  => md5_hex( $challenge . md5_hex( $key->hash ) )
        ),
        "$label challenge session exchange works"
    );
    ok( $u->session->valid, "$label challenge session validates" );
    my $form = { usertype => 'user', userpost => $u->user, password => 'compat-password' };
    $remote = undef;
    my ( $ok, $result ) =
        DW::Controller::Talk::authenticate_user_and_mutate_form( $form, undef, $u );
    is( $ok ? 1 : 0, $protected ? 0 : 1, "$label inline comment password behavior" );

    if ($protected) {
        ok( !$old->valid, 'Unverified pre-enrollment session is invalid' );
    }
    my %flags;
    my %entry_auth =
        DW::Controller::Entry::_auth( \%flags,
        { username => $u->user, password => 'compat-password' },
        undef, 'http://localhost/' );
    is( $entry_auth{poster} ? 1 : 0, $protected ? 0 : 1, "$label inline entry password behavior" );
    my @before = DW::Auth::TOTP->get_recovery_codes($u);
    ok( $u->make_fake_login_session, "$label admin impersonation succeeds" );
    ok( $u->session->valid,          "$label impersonated session validates" );
    is_deeply( [ DW::Auth::TOTP->get_recovery_codes($u) ],
        \@before, "$label impersonation does not consume target codes" );

    if ($protected) {
        $remote = $u;
        my ( $again, $who ) = DW::Controller::Talk::authenticate_user_and_mutate_form(
            { usertype => 'user', userpost => $u->user, password => '' },
            $u, $u );
        ok( $again && $who->{user}->equals($u), 'Protected comment can continue after sign-in' );
        $u->set_password('changed-password');
        ok( DW::Auth::TOTP->is_enabled($u), 'Password change preserves enabled factor' );
    }
}

{
    my $u = temp_user();
    $u->set_password('enrollment-password');
    my $other   = LJ::Session->create( $u, exptype => 'long' );
    my $current = LJ::Session->create( $u, exptype => 'long' );
    ok(
        DW::Auth::TOTP->enable(
            $u, DW::Auth::TOTP->generate_secret,
            'enrollment-password', $current
        ),
        'Enrollment preserves the verified browser'
    );
    ok( $current->valid, 'Enrolling browser stays signed in' );
    ok( !LJ::Session->instance( $u, $other->id ), 'Other browser is signed out' );
    my $verified_other = LJ::Session->create( $u, exptype => 'long' );
    DW::Auth::TOTP->mark_session( $u, $verified_other,
        DW::Auth::TOTP->_factor_state($u)->{factor} );
    my @codes = DW::Auth::TOTP->get_recovery_codes($u);
    ok( !DW::Auth::TOTP->disable( $u, 'enrollment-password', 'bad-code' ),
        'Disabling requires second factor' );
    ok( DW::Auth::TOTP->disable( $u, 'enrollment-password', $codes[0] ), 'Disable succeeds' );
    ok( $current->valid, 'Disabling browser stays signed in' );
    ok(
        LJ::Session->instance( $u, $verified_other->id )->valid,
        'Disable preserves existing other sessions'
    );
}

{
    my $u = temp_user();
    $u->set_password('login-password');
    $u->update_self( { status => 'A' } );
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
    my @codes = DW::Auth::TOTP->get_recovery_codes($u);
    $remote = undef;
    my $token = DW::Auth::Login->begin( $u, password => 'login-password', exptype => 'long' );
    ok( $token, 'Protected login begins' );
    ok( !DW::Auth::Login->complete( $u, grant => $token ), 'Unverified challenge cannot complete' );
    my ( $verified, $opts ) = DW::Auth::Login->verify( $token, $codes[0] );
    ok( $verified, 'Recovery code verifies challenge' );
    ok( !DW::Auth::TOTP->verify( $u, $codes[0] ), 'Recovery code cannot replay' );
    {
        local *LJ::UniqCookie::current_uniq = sub { 'different-browser' };
        ok(
            !DW::Auth::Login->complete( $u, %$opts ),
            'Verified grant cannot move to another browser'
        );
    }
    ok( DW::Auth::Login->complete( $u, %$opts ), 'Verified grant completes login' );
    ok( $u->session->valid, 'Completed browser session has valid factor proof' );
    ok( !DW::Auth::Login->complete( $u, %$opts ), 'Completed grant cannot replay' );
    my @totp = DW::Auth::TOTP->_get_codes($u);
    ok( DW::Auth::TOTP->verify( $u, $totp[-1] ), 'Current authenticator code accepted' );
    ok( !DW::Auth::TOTP->verify( $u, $totp[-1] ), 'Authenticator code cannot replay' );
    my $pending = DW::Auth::Login->begin( $u, password => 'login-password' );
    $u->set_password('replacement-password');
    ok( !DW::Auth::Login->pending($pending), 'Password change invalidates pending challenge' );
}

# Password changes serialize the factor decision with enrollment, without adding
# a code requirement for ordinary accounts. Exercise the real settings handler.
{
    local *DW::Template::render_template  = sub { $_[2] };
    local *DW::Controller::render_success = sub { 'success' };
    local *LJ::send_mail                  = sub { 1 };
    local *LJ::create_url                 = sub { '/login' };
    local *LJ::login_ip_banned            = sub { 0 };
    local *LJ::handle_bad_login           = sub { 1 };
    $remote = undef;
    local *DW::Controller::Settings::controller = sub {
        ( 1, { r => $request, remote => undef } );
    };
    for my $enroll ( 0, 1 ) {
        my $u = temp_user();
        $u->set_password('Original-pass-42');
        $u->update_self( { status => 'A' } );
        local $request->{post} = {
            mode     => 'submit',
            user     => $u->user,
            password => 'Original-pass-42',
            newpass1 => 'Replacement-pass-73',
            newpass2 => 'Replacement-pass-73'
        };
        my $check_password = \&LJ::User::check_password;
        my $checked        = 0;
        local *LJ::User::check_password = sub {
            my $ok = $check_password->(@_);

            # Finish enrollment after the request's first password check.
            DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret )
                if $enroll && !$checked++;
            return $ok;
        };
        my $result = DW::Controller::Settings::changepassword_handler();
        if ( !$enroll ) {
            is( $result, 'success', 'Ordinary password change still needs no code' );
            ok( $u->check_password('Replacement-pass-73'), 'Ordinary new password works' );
            next;
        }
        ok( $result->{errors}->exist, 'Enrollment during request prevents password-only change' );
        ok( $u->check_password('Original-pass-42'), 'Rejected request leaves password unchanged' );
        my @codes = DW::Auth::TOTP->get_recovery_codes($u);
        $request->{post}{code} = $codes[0];
        {
            local *LJ::User::set_password = sub { die "Injected password write failure\n" };
            eval { DW::Controller::Settings::changepassword_handler() };
            like( $@, qr/Injected password write failure/, 'Password write error is reported' );
            my @remaining = DW::Auth::TOTP->get_recovery_codes($u);
            ok(
                scalar( grep { $_ eq $codes[0] } @remaining ),
                'Failed password update rolls code consumption back'
            );
        }
        is( DW::Controller::Settings::changepassword_handler(),
            'success', 'Protected password change succeeds with recovery code' );
        ok( $u->check_password('Replacement-pass-73'), 'Protected new password works' );
        ok( !DW::Auth::TOTP->verify( $u, $codes[0] ), 'Successful change consumes code' );
        ok( DW::Auth::TOTP->is_enabled($u), 'Password change preserves factor' );
    }
}

# A 2FA-enabled WSSE account accepts its API key, but not its password.
{
    my $created = POSIX::strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime );
    my $u       = temp_user();
    $u->set_password('wsse-password');
    my $key = DW::API::Key->new_for_user($u);
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
    for my $credential ( 'wsse-password', $key->hash ) {
        my $nonce  = 'compat-' . $u->id . '-' . length($credential);
        my $digest = Digest::SHA1::sha1_base64( $nonce . $created . $credential );
        my ($who) =
            DW::Auth::_auth_wsse( 'UsernameToken Username="'
                . $u->user
                . '", PasswordDigest="'
                . $digest
                . '", Nonce="'
                . $nonce
                . '", Created="'
                . $created
                . '"' );
        is(
            $who                      ? $who->id : 0,
            $credential eq $key->hash ? $u->id   : 0,
            'WSSE authenticates a 2FA-enabled account only with its API key'
        );
    }
}

# An authorized administrator can impersonate a 2FA-enabled account.
{
    my $admin = temp_user();
    $admin->set_password('admin-password');
    my $target = temp_user();
    $target->set_password('target-password');
    DW::Auth::TOTP->enable( $target, DW::Auth::TOTP->generate_secret );
    $remote = $admin;
    local $request->{post} = {
        username => $target->user,
        password => 'admin-password',
        reason   => 'Compatibility regression'
    };
    local *DW::Controller::Admin::UserViews::controller = sub {
        return ( 1, { r => $request, remote => $admin } );
    };
    local *LJ::User::logout      = sub { $remote = undef };
    local *LJ::User::log_event   = sub { 1 };
    local *LJ::statushistory_add = sub { 1 };
    is( DW::Controller::Admin::UserViews::impersonate_controller(),
        $LJ::SITEROOT, 'Admin controller completes impersonation of protected account' );
    ok(
        $remote->equals($target) && $remote->session->valid,
        'Published impersonation session is usable'
    );
}

# A failed MFA publication can retry the verified grant without another code.
{
    my $u = temp_user();
    $u->set_password('retry-password');
    $u->update_self( { status => 'A' } );
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
    my @codes = DW::Auth::TOTP->get_recovery_codes($u);
    $remote = undef;
    my $token = DW::Auth::Login->begin( $u, password => 'retry-password' );
    my ( $verified, $opts ) = DW::Auth::Login->verify( $token, $codes[0] );
    {
        local *LJ::User::publish_login_session = sub { die 'Publication failure' };
        ok( !DW::Auth::Login->complete( $u, %$opts ), 'Failed protected login reports failure' );
    }
    is( scalar LJ::Session->active_sessions($u),
        0, 'Failed protected login leaves no usable session' );
    ok( DW::Auth::Login->complete( $u, %$opts ), 'Verified grant can retry publication' );
    is( scalar DW::Auth::TOTP->get_recovery_codes($u), 9, 'Retry consumes only one code' );
}

{
    local *DW::Controller::Mobile::Login::controller =
        sub { ( 1, { r => $request, remote => undef } ) };
    for my $protected ( 0, 1 ) {
        my $u = temp_user();
        $u->set_password('mobile-password');
        DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret ) if $protected;
        $remote = undef;
        local $request->{post} = { user => $u->user, password => 'mobile-password' };
        my $destination = DW::Controller::Mobile::Login::login_handler();
        like(
            $destination,
            $protected ? qr{/login/2fa$} : qr{/mobile/},
            'Mobile login challenges only protected accounts'
        );
    }
}

with_fake_memcache {
    my $u = temp_user();
    $u->set_password('setup-password');
    my $session = LJ::Session->create( $u, exptype => 'long' );
    $u->{_session} = $session;
    my $secret = DW::Auth::TOTP->generate_secret;
    ok(
        !DW::Auth::TOTP->enable( $u, $secret, 'setup-password', $session, 'invalid' ),
        'Enrollment rejects an invalid setup code inside the transaction'
    );
    ok( !DW::Auth::TOTP->is_enabled($u), 'Rejected enrollment leaves factor disabled' );
    ok( $session->valid,                 'Rejected enrollment keeps the current session' );
    my $inactive = temp_user( cluster => $u->clusterid );
    my $dbh      = LJ::get_cluster_master($u);
    $dbh->do( 'INSERT INTO mfa_sessions (userid, sessid, factor, expires) VALUES (?, ?, ?, ?)',
        undef, $inactive->id, 999, 'x' x 64, time() - 10 );
    local *DW::Controller::Settings::controller = sub { ( 1, { r => $request, remote => $u } ) };
    local *DW::Template::render_template        = sub { $_[2] };
    my @codes = DW::Auth::TOTP->_get_codes( $u, secret => $secret );
    local $request->{post} = {
        'action:enable'   => 1,
        password          => 'setup-password',
        totp_secret       => $secret,
        verification_code => $codes[-1]
    };
    my $result = DW::Controller::Settings::manage2fa_handler();
    ok(
        DW::Auth::TOTP->is_enabled($u) && $session->valid,
        'Setup enables 2FA and retains the current browser session'
    );
    ok( !DW::Auth::TOTP->verify( $u, $codes[-1] ), 'Enrollment code cannot be reused to log in' );
    is(
        $dbh->selectrow_array(
            'SELECT COUNT(*) FROM mfa_sessions WHERE userid=?',
            undef, $inactive->id
        ),
        0,
        'Proof cleanup includes expired rows of inactive accounts'
    );
    my $legacy = temp_user();
    $legacy->update_self( { dversion => 9 } );
    local *DW::Controller::Settings::controller =
        sub { ( 1, { r => $request, remote => $legacy } ) };

    for my $action (qw(action:setup action:enable)) {
        $request->{post} = { $action => 1 };
        my $result = DW::Controller::Settings::manage2fa_handler();
        ok(
            $result->{message} && !DW::Auth::TOTP->is_enabled($legacy),
            'Legacy storage enrollment reports an error and leaves 2FA disabled'
        );
    }
};

{
    my $u = temp_user();
    $u->set_password('race-password');
    my $auth = \&LJ::auth_okay;
    local *LJ::auth_okay = sub {
        my $ok = $auth->(@_);
        DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
        return $ok;
    };
    my ( $ok, $error ) = DW::Controller::Talk::authenticate_user_and_mutate_form(
        { usertype => 'user', userpost => $u->user, password => 'race-password' },
        undef, $u );
    ok( !$ok, 'Comment requires MFA if enrollment completes during password verification' );
}

{
    my $u = temp_user();
    $u->set_password('locked-password');
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
    local *DW::Controller::Mobile::Login::controller = sub {
        ( 1, { r => $request, remote => undef } );
    };
    local *DW::Template::render_template = sub { $_[2] };
    local $request->{post} = { user => $u->user, password => 'locked-password' };
    for my $status (qw(L O)) {
        $u->update_self( { statusvis => $status } );
        my $result = DW::Controller::Mobile::Login::login_handler();
        ok( $result->{errors}->exist, 'Protected unavailable account gets a mobile form error' );
    }
}
with_fake_memcache {
    my $u = temp_user();
    $u->set_password('conflict-password');
    my $secret = DW::Auth::TOTP->generate_secret;
    DW::Auth::TOTP->enable( $u, $secret );
    my @before  = DW::Auth::TOTP->get_recovery_codes($u);
    my $enabled = \&DW::Auth::TOTP::is_enabled;

    # Model the stale pre-lock read of a second enrollment request.
    {
        local *DW::Auth::TOTP::is_enabled = sub { 0 };
        ok( !DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret, 'conflict-password' ),
            'Losing enrollment returns failure instead of throwing' );
    }
    is_deeply( [ DW::Auth::TOTP->get_recovery_codes($u) ],
        \@before, 'Losing enrollment preserves the winning recovery codes' );
    my $unverified = LJ::Session->create( $u, exptype => 'long' );
    ok( !$unverified->valid, 'Losing enrollment does not authorize password-only sessions' );
    local *DW::Controller::Settings::controller = sub { ( 1, { r => $request, remote => $u } ) };
    local *DW::Template::render_template        = sub { $_[2] || {} };
    my $checks = 0;
    local *DW::Auth::TOTP::is_enabled = sub { return 0 unless $checks++; return $enabled->(@_) };
    my @codes = DW::Auth::TOTP->_get_codes( $u, secret => $secret );
    local $request->{post} = {
        'action:enable'   => 1,
        password          => 'conflict-password',
        totp_secret       => $secret,
        verification_code => $codes[-1]
    };
    my $result = DW::Controller::Settings::manage2fa_handler();
    ok( !$result->{codes} && !$result->{show_codes},
        'Conflicting enrollment does not disclose recovery codes' );
    is_deeply( [ DW::Auth::TOTP->get_recovery_codes($u) ],
        \@before, 'Conflicting enrollment leaves the original recovery codes usable' );
};
{
    my $u = temp_user();
    $u->set_password('partial-password');
    my $current = LJ::Session->create( $u, exptype => 'long' );
    my $other   = LJ::Session->create( $u, exptype => 'long' );
    {
        local *DW::Auth::TOTP::mark_session = sub { die "Injected proof write failure\n" };
        eval {
            DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret,
                'partial-password', $current );
        };
        like( $@, qr/Injected proof write failure/, 'Enrollment reports a failed proof write' );
    }
    ok( !DW::Auth::TOTP->is_enabled($u), 'Failed enrollment rolls back the factor' );
    ok( $current->valid,                 'Failed enrollment preserves the enrolling browser' );
    ok( !LJ::Session->instance( $u, $other->id ),
        'Already deleted cluster sessions stay signed out after enrollment rollback' );
}

for my $protected ( 0, 1 ) {
    my $u = temp_user();
    $u->set_password('ban-password');
    my $key = DW::API::Key->new_for_user($u);
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret ) if $protected;
    local *LJ::login_ip_banned = sub { 1 };
    my $error;
    ok(
        !LJ::Protocol::authenticate(
            { username => $u->user, password => $key->hash }, \$error, {}
        ),
        'Banned clear-auth request is rejected'
    );
    is( $error, 402, 'Ordinary and protected clients receive the same temporary-ban error' );
}

# Clear API authentication keeps the existing personal-account restriction
# when an enrolled account is later converted to a community.
for my $protected ( 0, 1 ) {
    my $u = temp_user();
    $u->set_password('account-type-password');
    my $key = DW::API::Key->new_for_user($u);
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret ) if $protected;
    my $label = $protected ? 'Protected' : 'Ordinary';
    ok( protocol_auth( $u, password => $key->hash ), "$label personal account accepts its key" );
    $u->update_self( { journaltype => 'C' } );
    ok(
        !protocol_auth( $u, password => $key->hash ),
        "$label community rejects clear API-key authentication"
    );
    ok(
        !protocol_auth( $u, hpassword => md5_hex( $key->hash ) ),
        "$label community rejects hashed clear API-key authentication"
    );
    ok( !exchange( $u, password => $key->hash ),
        "$label community cannot exchange a clear API key for a session" );
}
{
    my $u = temp_user();
    local *LJ::Session::create = sub { undef };
    eval { $u->make_login_session('long') };
    ok( $@,           'Ordinary login reports failed session allocation' );
    ok( !$u->session, 'Failed allocation does not create a login session' );
}

# Proof storage follows the user's cluster, including uncached reads and renewal.
for my $cluster (@LJ::CLUSTERS) {
    with_fake_memcache {
        my $u = temp_user( cluster => $cluster );
        $u->set_password('cluster-password');
        DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
        my $session = LJ::Session->create( $u, exptype => 'short' );
        my $factor  = DW::Auth::TOTP->_factor_state($u)->{factor};
        ok(
            DW::Auth::TOTP->mark_session( $u, $session, $factor ),
            "Cluster $cluster stores session authorization"
        );
        my $dbh = LJ::get_cluster_master($u);
        is(
            $dbh->selectrow_array(
                'SELECT factor FROM mfa_sessions WHERE userid=? AND sessid=?', undef,
                $u->id,                                                        $session->id
            ),
            $factor,
            'Proof is stored beside the user session'
        );
        my $key = DW::Auth::TOTP->_proof_key( $u->id, $session->id );
        LJ::MemCache::delete($key);
        {
            local *LJ::get_db_writer = sub { die 'Unexpected central database access' };
            is( DW::Auth::TOTP->_session_proof($session)->{factor},
                $factor, 'Uncached proof reads use only the user cluster' );
            ok( $session->set_exptype('long'), 'Session renewal uses the user cluster' );
        }
        is(
            $dbh->selectrow_array(
                'SELECT expires FROM mfa_sessions WHERE userid=? AND sessid=?', undef,
                $u->id,                                                         $session->id
            ),
            $session->expiration_time,
            'Proof expiration follows session renewal'
        );
        $dbh->do(
            'UPDATE mfa_sessions SET expires=? WHERE userid=? AND sessid=?',
            undef, time() - 1,
            $u->id, $session->id
        );
        LJ::MemCache::delete($key);
        ok( !$session->valid, 'Expired cluster proof cannot authorize a live session' );
        $session->set_exptype('long');
        ok( !$session->valid, 'Renewal cannot revive an expired cluster proof' );
    };
}

# A cluster proof can survive a central rollback, but its factor must not authorize
# a later enrollment. The enrolling browser retains its original ordinary session.
with_fake_memcache {
    my $u = temp_user();
    $u->set_password('rollback-password');
    my $session = LJ::Session->create( $u, exptype => 'long' );
    my $mark    = \&DW::Auth::TOTP::mark_session;
    {
        local *DW::Auth::TOTP::mark_session = sub {
            $mark->(@_);
            die "Failure after cluster proof write\n";
        };
        eval {
            DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret,
                'rollback-password', $session );
        };
        like(
            $@,
            qr/Failure after cluster proof write/,
            'Enrollment fails after writing cluster proof'
        );
    }
    ok( !DW::Auth::TOTP->is_enabled($u), 'Central factor rolls back' );
    ok( $session->valid,                 'Original ordinary session remains valid after rollback' );
    my $stale = DW::Auth::TOTP->_session_proof($session);
    ok( $stale->{factor}, 'Cluster proof survives the central rollback' );
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
    ok(
        !DW::Auth::TOTP->session_verified($session),
        'Stale proof cannot authorize a different enrollment'
    );
};

SKIP: {
    skip 'Account movement requires two test clusters', 5 unless @LJ::CLUSTERS >= 2;
    my ( $source, $destination ) = @LJ::CLUSTERS;
    my $u = temp_user( cluster => $source );
    $u->set_password('moving-password');
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
    my $session = LJ::Session->create( $u, exptype => 'long' );
    DW::Auth::TOTP->mark_session( $u, $session, DW::Auth::TOTP->_factor_state($u)->{factor} );
    local $ENV{DW_TEST} = 1;
    is(
        system(
            "$ENV{LJHOME}/bin/moveucluster.pl",
            '--ignorebit', '--destdel', '--delete', '--verbose=0', $u->user, $destination
        ),
        0,
        'Existing cluster mover handles session proofs'
    );

    # Model the next web request, without the source cluster's cached DB handle.
    DW::Cache->request->clear_ns('user_id');
    DW::Cache->request->clear_ns('user_name');
    $u = LJ::load_user( $u->user, 'force' );
    is( $u->clusterid, $destination, 'Protected account moves to the destination cluster' );
    is(
        LJ::get_cluster_master($source)
            ->selectrow_array( 'SELECT COUNT(*) FROM mfa_sessions WHERE userid=?', undef, $u->id ),
        0,
        'Source cluster proof is removed after movement'
    );
    is(
        LJ::get_cluster_master($destination)
            ->selectrow_array( 'SELECT COUNT(*) FROM mfa_sessions WHERE userid=?', undef, $u->id ),
        1,
        'Destination cluster contains the session proof'
    );
    LJ::MemCache::delete( DW::Auth::TOTP->_proof_key( $u->id, $session->id ) );
    my $moved = LJ::Session->instance( $u, $session->id );
    ok( $moved && $moved->valid, 'Moved session remains authorized with an uncached proof' );
}

# Expiration prevents both accepting a code and completing an already verified login.
for my $verified ( 0, 1 ) {
    my $u = temp_user();
    $u->set_password('expiry-password');
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
    my @codes = DW::Auth::TOTP->get_recovery_codes($u);
    my $token = DW::Auth::Login->begin( $u, password => 'expiry-password' );
    ok( DW::Auth::Login->verify( $token, $codes[0] ), 'Code verifies before expiration' )
        if $verified;

    # Age the stored challenge rather than sleeping through its lifetime.
    LJ::get_db_writer()->do(
        'UPDATE login_challenges SET expires=? WHERE token=?',
        undef, time() - 1,
        sha256_hex($token)
    );
    ok( !DW::Auth::Login->verify( $token, $codes[1] ), 'Expired challenge rejects a valid code' );
    ok( !DW::Auth::Login->complete( $u, grant => $token ),
        'Expired challenge cannot create a session, even after verification' );
    is( scalar LJ::Session->active_sessions($u), 0, 'Expired login leaves no session' );
    ok(
        DW::Auth::TOTP->verify( $u, $codes[1] ),
        'Rejected expired login does not consume the code'
    );
}

# Exercise failed attempts through verification, not by setting the counter.
# Isolate the challenge limits from the independent IP-based login throttle.
for my $challenges ( 1, 4 ) {
    local *LJ::login_ip_banned  = sub { 0 };
    local *LJ::handle_bad_login = sub { 1 };
    my $u = temp_user();
    $u->set_password('attempt-password');
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
    my @codes = DW::Auth::TOTP->get_recovery_codes($u);
    my $token;
    my $accepted = 0;

    for ( 1 .. $challenges ) {
        $token = DW::Auth::Login->begin( $u, password => 'attempt-password' );
        for ( 1 .. 5 ) {
            $accepted++ if DW::Auth::Login->verify( $token, 'invalid-code' );
        }
    }
    is( $accepted, 0, 'Incorrect codes never verify a challenge' );
    ok(
        !DW::Auth::Login->verify( $token, $codes[0] ),
        'Exhausted challenge rejects even a valid code'
    );
    ok(
        !DW::Auth::Login->complete( $u, grant => $token ),
        'Exhausted challenge cannot complete login'
    );
    my $fresh = DW::Auth::Login->begin( $u, password => 'attempt-password' );
    if ( $challenges == 4 ) {
        ok( !DW::Auth::Login->verify( $fresh, $codes[0] ),
            'New challenges cannot bypass the account-wide attempt limit' );
        LJ::get_db_writer()->do( 'UPDATE login_challenges SET expires=? WHERE userid=?',
            undef, time() - 1, $u->id );
        $fresh = DW::Auth::Login->begin( $u, password => 'attempt-password' );
    }
    my ( $owner, $opts ) = DW::Auth::Login->verify( $fresh, $codes[0] );
    ok(
        $owner && DW::Auth::Login->complete( $owner, %$opts ) && $u->session->valid,
        $challenges == 4
        ? 'Login succeeds after the account attempt window expires'
        : 'Restarting login works below the account attempt limit'
    );
}

done_testing();
