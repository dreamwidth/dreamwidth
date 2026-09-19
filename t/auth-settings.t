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
use LJ::Test qw(temp_user);
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
    local *LJ::User::logout                  = sub { ++$logouts };
    local *LJ::User::make_fake_login_session = sub { ++$impersonations };
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
done_testing();
