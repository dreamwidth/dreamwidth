#!/usr/bin/perl
#
# t/auth-settings.t
#
# Regression tests for second-factor settings and password changes.
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
use DW::Controller::Settings;
use DW::Controller::Admin::UserViews;
use DW::Auth::TOTP;

{

    package SettingsAuthRequest;
    sub post_args     { $_[0]->{post} }
    sub get_args      { {} }
    sub did_post      { 1 }
    sub note          { undef }
    sub get_remote_ip { '127.0.0.1' }
    sub redirect      { $_[1] }
}
my $r = bless { post => {} }, 'SettingsAuthRequest';
my $u = temp_user();
$u->set_password('test-password');
$u->update_self( { status => 'A' } );
my $secret   = DW::Auth::TOTP->generate_secret;
my $failures = 0;
no warnings 'redefine';
local *DW::Request::get                     = sub { $r };
local *DW::Controller::Settings::controller = sub { ( 1, { r => $r, remote => $u } ) };
local *DW::Template::render_template        = sub { $_[2] };
local *LJ::get_remote                       = sub { $u };
local *LJ::handle_bad_login                 = sub { ++$failures };
local *LJ::login_ip_banned                  = sub { 0 };

for my $enabled ( 0, 1 ) {
    DW::Auth::TOTP->enable( $u, $secret ) if $enabled;
    my $action = $enabled ? 'action:show-codes' : 'action:enable';
    for my $password ( 'wrong-password', 'test-password' ) {
        $failures = 0;
        $r->{post} = {
            $action           => 1,
            password          => $password,
            totp_secret       => $secret,
            verification_code => 'invalid',
            code              => 'invalid'
        };
        my $result = DW::Controller::Settings::manage2fa_handler();
        ok( $result->{errors}->exist, "$action rejects incorrect credentials" );
        is( $failures, 1, "$action counts $password failure once" );
    }
}
my @codes   = DW::Auth::TOTP->get_recovery_codes($u);
my @invalid = (
    [ '',                '',          'blank password' ],
    [ 'Another-pass-42', 'different', 'mismatched passwords' ],
    [ 'x',               'x',         'policy-invalid password' ],
);
for my $case (@invalid) {
    $r->{post} = {
        mode     => 'submit',
        user     => $u->user,
        password => 'test-password',
        newpass1 => $case->[0],
        newpass2 => $case->[1],
        code     => $codes[0]
    };
    my $result = DW::Controller::Settings::changepassword_handler();
    ok( $result->{errors}->exist, "Reject $case->[2]" );
    my @remaining = DW::Auth::TOTP->get_recovery_codes($u);
    ok( scalar( grep { $_ eq $codes[0] } @remaining ),
        "$case->[2] does not consume recovery code" );
}
$r->{post} = {
    mode     => 'submit',
    user     => $u->user,
    password => 'test-password',
    newpass1 => 'Another-pass-42',
    newpass2 => 'Another-pass-42',
    code     => $codes[0]
};
{
    my $set_password = \&LJ::User::set_password;
    local *LJ::User::set_password = sub {
        $set_password->(@_);
        die "Injected password write failure\n";
    };
    eval { DW::Controller::Settings::changepassword_handler() };
    like( $@, qr/Injected password write failure/, 'Password write failure is reported' );
    my @remaining = DW::Auth::TOTP->get_recovery_codes($u);
    ok(
        scalar( grep { $_ eq $codes[0] } @remaining ),
        'Failed password update rolls factor consumption back'
    );
    ok( $u->check_password('test-password'), 'Failed update leaves original password valid' );
}
{
    local *LJ::send_mail                  = sub { 1 };
    local *DW::Controller::render_success = sub { 'success' };
    local *LJ::create_url                 = sub { '/login' };
    is( DW::Controller::Settings::changepassword_handler(),
        'success', 'Valid password and code update password' );
    ok( $u->check_password('Another-pass-42'), 'New password works' );
    ok( !DW::Auth::TOTP->verify( $u, $codes[0] ), 'Successful password update consumes code' );
    ok( DW::Auth::TOTP->is_enabled($u), 'Password change preserves second factor' );
}
{
    my $admin = temp_user();
    $admin->set_password('admin-password');
    local *DW::Controller::Admin::UserViews::controller =
        sub { ( 1, { r => $r, remote => $admin } ) };
    local *LJ::check_referer = sub { 1 };
    my ( $logouts, $impersonations ) = ( 0, 0 );
    local *LJ::User::logout                = sub { ++$logouts };
    local *LJ::User::publish_login_session = sub { ++$impersonations };
    $r->{post} = {
        username => $u->user,
        password => 'admin-password',
        reason   => 'Test impersonation policy'
    };
    my $result = DW::Controller::Admin::UserViews::impersonate_controller();
    ok( $result->{errors}->exist, 'Impersonation refuses a TOTP-protected target' );
    is( $logouts,        0, 'Denied impersonation retains administrator session' );
    is( $impersonations, 0, 'Denied impersonation creates no target session' );
}
with_fake_memcache {
    my $account = temp_user();
    $account->set_password('cache-repair-password');
    $account->update_self( { status => 'A' } );
    local *DW::Controller::Settings::controller = sub { ( 1, { r => $r, remote => $account } ) };
    local *LJ::get_remote                       = sub { $account };
    my $setup_secret = DW::Auth::TOTP->generate_secret;
    my @setup_codes  = DW::Auth::TOTP->_get_codes( $account, secret => $setup_secret );
    my $result;
    {
        local *DW::Auth::TOTP::_factor_state = sub { die 'Cache refresh unavailable' };
        $r->{post} = {
            'action:enable'   => 1,
            password          => 'cache-repair-password',
            totp_secret       => $setup_secret,
            verification_code => $setup_codes[1]
        };
        $result = DW::Controller::Settings::manage2fa_handler();
    }
    ok( $result->{just_enabled}, 'Post-commit cache failure still reports successful enrollment' );
    is( scalar @{ $result->{codes} }, 10, 'Enrollment still displays recovery codes' );
    ok( DW::Auth::TOTP->is_enabled($account), 'Enrollment remains committed' );
    my $plain = LJ::Session->create( $account, exptype => 'long', nolog => 1 );
    ok( !$plain->valid, 'Next reader repairs factor cache and still requires MFA' );
    {
        local *DW::Auth::TOTP::_factor_state = sub { die 'Cache refresh unavailable' };
        $r->{post} = {
            'action:disable-confirm' => 1,
            password                 => 'cache-repair-password',
            code                     => $result->{codes}[0]
        };
        $result = DW::Controller::Settings::manage2fa_handler();
    }
    ok( $result->{just_disabled}, 'Post-commit cache failure still reports successful disable' );
    ok( !DW::Auth::TOTP->is_enabled($account), 'Disable remains committed' );
    $plain = LJ::Session->create( $account, exptype => 'long', nolog => 1 );
    ok( $plain->valid, 'Next reader repairs disabled factor cache' );
};
{
    my $account = temp_user();
    $account->set_password('enrollment-old-password');
    $account->update_self( { status => 'A' } );
    my $secret = DW::Auth::TOTP->generate_secret;
    my @totp   = DW::Auth::TOTP->_get_codes( $account, secret => $secret );
    local *DW::Controller::Settings::controller = sub { ( 1, { r => $r, remote => $account } ) };
    local *LJ::get_remote                       = sub { $account };
    my $enable = \&DW::Auth::TOTP::enable;
    local *DW::Auth::TOTP::enable = sub {

        # Another password change commits after the controller's initial check.
        $account->set_password('enrollment-new-password');
        return $enable->(@_);
    };
    $r->{post} = {
        'action:enable'   => 1,
        password          => 'enrollment-old-password',
        totp_secret       => $secret,
        verification_code => $totp[1]
    };
    my $result = DW::Controller::Settings::manage2fa_handler();
    ok( $result->{errors}->exist, 'Stale enrollment password is rejected under the factor lock' );
    ok( !DW::Auth::TOTP->is_enabled($account), 'Stale request cannot install its factor' );
}
{
    my $account = temp_user();
    $account->set_password('recovery-old-password');
    DW::Auth::TOTP->enable( $account, DW::Auth::TOTP->generate_secret );
    my @codes = DW::Auth::TOTP->get_recovery_codes($account);
    local *DW::Controller::Settings::controller = sub { ( 1, { r => $r, remote => $account } ) };
    my $read = \&DW::Auth::TOTP::recovery_codes_for_credentials;
    {
        local *DW::Auth::TOTP::recovery_codes_for_credentials = sub {
            $account->set_password('recovery-new-password');
            return $read->(@_);
        };
        $r->{post} =
            { 'action:show-codes' => 1, password => 'recovery-old-password', code => $codes[0] };
        my $result = DW::Controller::Settings::manage2fa_handler();
        ok(
            $result->{errors}->exist && !$result->{codes},
            'Stale password cannot disclose recovery codes'
        );
    }
    my $dbh    = LJ::get_db_writer();
    my $check  = \&DW::Auth::Password::check;
    my $verify = \&DW::Auth::TOTP::verify;
    my $get    = \&DW::Auth::TOTP::get_recovery_codes;
    {
        local *DW::Auth::Password::check = sub {
            ok( !$dbh->{AutoCommit}, 'Recovery password check is transactional' );
            return $check->(@_);
        };
        local *DW::Auth::TOTP::verify = sub {
            ok( !$dbh->{AutoCommit}, 'Recovery factor check is in the same transaction' );
            return $verify->(@_);
        };
        local *DW::Auth::TOTP::get_recovery_codes = sub {
            ok( !$dbh->{AutoCommit}, 'Recovery-code read is in the same transaction' );
            return $get->(@_);
        };
        my $remaining =
            DW::Auth::TOTP->recovery_codes_for_credentials( $account, 'recovery-new-password',
            $codes[0] );
        is( scalar @$remaining, 9, 'Authorized read consumes only its recovery code' );
    }
    {
        local *DW::Auth::TOTP::get_recovery_codes = sub { die 'Recovery-code read unavailable' };
        eval {
            DW::Auth::TOTP->recovery_codes_for_credentials( $account, 'recovery-new-password',
                $codes[1] );
        };
        like( $@, qr/Recovery-code read unavailable/, 'Read failure is surfaced' );
    }
    ok(
        DW::Auth::TOTP->verify( $account, $codes[1] ),
        'Failed disclosure rolls back code consumption'
    );
}
{
    my $admin = temp_user();
    $admin->set_password('admin-password');
    my $target = temp_user();
    $target->set_password('target-password');
    local *DW::Controller::Admin::UserViews::controller =
        sub { ( 1, { r => $r, remote => $admin } ) };
    local *LJ::check_referer = sub { 1 };
    my ( $logouts, $published ) = ( 0, 0 );
    local *LJ::User::logout                = sub { ++$logouts };
    local *LJ::User::publish_login_session = sub { ++$published };
    my $enabled = \&DW::Auth::TOTP::is_enabled;
    my $raced;
    local *DW::Auth::TOTP::is_enabled = sub {
        my $result = $enabled->(@_);
        if ( !$raced ) {
            $raced = 1;
            DW::Auth::TOTP->enable( $target, DW::Auth::TOTP->generate_secret );
        }
        elsif ($result) {
            ok( !LJ::get_db_writer()->{AutoCommit},
                'Impersonation rechecks factor inside account lock' );
        }
        return $result;
    };
    $r->{post} =
        { username => $target->user, password => 'admin-password', reason => 'Race regression' };
    my $result = DW::Controller::Admin::UserViews::impersonate_controller();
    ok( $result->{errors}->exist, 'Concurrent enrollment prevents impersonation' );
    is( $logouts,   0, 'Concurrent enrollment does not log administrator out' );
    is( $published, 0, 'Concurrent enrollment does not publish target session' );
}
{
    my $admin = temp_user();
    $admin->set_password('admin-password');
    my $target = temp_user();
    local *DW::Controller::Admin::UserViews::controller =
        sub { ( 1, { r => $r, remote => $admin } ) };
    local *LJ::check_referer = sub { 1 };
    my ( $logouts, $session, $fake );
    local *LJ::User::logout                = sub { ++$logouts };
    local *LJ::User::publish_login_session = sub {
        ( $session, $fake ) = @_[ 1, 2 ];
        ok( !LJ::get_db_writer()->{AutoCommit},
            'Impersonation retains account lock through publication' );
        return 1;
    };
    $r->{post} = {
        username => $target->user,
        password => 'admin-password',
        reason   => 'Ordinary target regression'
    };
    DW::Controller::Admin::UserViews::impersonate_controller();
    is( $logouts, 1, 'Permitted impersonation logs administrator out' );
    ok(
        $session && $session->owner->equals($target) && $session->valid && $fake,
        'Permitted impersonation publishes a valid target session without login activity'
    );
}
{
    my $admin = temp_user();
    $admin->set_password('admin-old-password');
    my $target = temp_user();
    local *DW::Controller::Admin::UserViews::controller =
        sub { ( 1, { r => $r, remote => $admin } ) };
    local *LJ::check_referer = sub { 1 };
    my ( $logouts, $published, $raced ) = ( 0, 0, 0 );
    local *LJ::User::logout                = sub { ++$logouts };
    local *LJ::User::publish_login_session = sub { ++$published };
    my $check = \&DW::Auth::Password::check;
    local *DW::Auth::Password::check = sub {
        my $valid = $check->(@_);
        $admin->set_password('admin-new-password') unless $raced++;
        return $valid;
    };
    $r->{post} = {
        username => $target->user,
        password => 'admin-old-password',
        reason   => 'Credential race regression'
    };
    my $result = DW::Controller::Admin::UserViews::impersonate_controller();
    ok( $result->{errors}->exist, 'Impersonation rechecks administrator credentials under lock' );
    is( $logouts,   0, 'Stale administrator password does not replace existing session' );
    is( $published, 0, 'Stale administrator password does not publish target session' );
}
done_testing();
