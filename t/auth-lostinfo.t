#!/usr/bin/perl
#
# t/auth-lostinfo.t
#
# Account selection and mail delivery boundaries for lost account information.
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Controller::Settings;
use LJ::Identity;
use LJ::Test qw(temp_user temp_comm);

{

    package LostInfoRequest;
    sub post_args     { $_[0]->{post} }
    sub did_post      { 1 }
    sub get_remote_ip { '127.0.0.1' }
}

{

    package LostInfoCaptcha;
    sub validate { 1 }
}

my $request = bless { post => {} }, 'LostInfoRequest';
my ( @mail, @actions, @rated );
my %limited;

# Exercise the real account lookup, display names and recovery-address checks.
# Replace the request shell, rendering and delivery so no mail can be queued.
no warnings 'redefine';
local *DW::Controller::Settings::controller = sub { ( 1, { r => $request } ) };
local *DW::Controller::Settings::error_ml   = sub { $_[0] };
local *DW::Controller::render_success       = sub { $_[1] };
local *DW::Captcha::new                     = sub { bless {}, 'LostInfoCaptcha' };
local *LJ::send_mail = sub {
    push @mail, { %{ $_[0] } };
    return 1;
};
local *LJ::register_authaction = sub {
    push @actions, [@_];
    return { aaid => 2439, authcode => 'local-test-token' };
};
local *LJ::sysban_check   = sub { 0 };
local *LJ::User::rate_log = sub {
    my ($u) = @_;
    push @rated, $u->id;
    return !$limited{ $u->id };
};
local $LJ::BLOCKED_PASSWORD_EMAIL = undef;

sub submit_lostinfo {
    my (%post) = @_;
    @mail = @actions = @rated = ();
    $request->{post} = \%post;
    return DW::Controller::Settings::lostinfo_handler();
}

my $personal = temp_user();
my $identity = temp_user( journaltype => 'I' );
my $comm     = temp_comm();
my $purged   = temp_user();
my $email    = 'lostinfo-' . $personal->id . '@example.invalid';
for my $u ( $personal, $identity, $comm, $purged ) {
    $u->set_email($email);
}
$personal->update_self( { status    => 'A' } );
$purged->update_self(   { statusvis => 'X' } );

my $dbh        = LJ::get_db_writer();
my $openid_url = 'https://openid.example.invalid/' . $identity->user;
$dbh->do( 'INSERT INTO identitymap (idtype, identity, userid) VALUES (?, ?, ?)',
    undef, 'O', $openid_url, $identity->id );
die $dbh->errstr if $dbh->err;
my $openid_name = $identity->display_name;
ok( $openid_name && $openid_name ne $identity->user, 'OpenID fixture has a display name' );

subtest 'username mail contains individuals and omits communities' => sub {
    is( submit_lostinfo( lostuser => 1, email_u => $email ),
        'settings/lostuser.tt', 'reminder succeeds for a shared email' );
    is( scalar @mail,   1,      'one reminder is captured' );
    is( $mail[0]->{to}, $email, 'reminder goes to the requested address' );
    my $body = $mail[0]->{body} // '';
    like( $body, qr/\Q@{[ $personal->user ]}\E/, 'personal username is included' );
    like( $body, qr/\Q$openid_name\E/,           'OpenID display name is included' );
    unlike( $body, qr/\Q@{[ $comm->user ]}\E/,   'community is omitted' );
    unlike( $body, qr/\Q@{[ $purged->user ]}\E/, 'purged account remains omitted' );
    is_deeply(
        [ sort { $a <=> $b } @rated ],
        [ sort { $a <=> $b } ( $personal->id, $identity->id ) ],
        'only eligible accounts consume the reminder rate limit'
    );
    is_deeply( \@actions, [], 'username reminders create no password reset tokens' );
};

subtest 'community rate limits do not block eligible reminders' => sub {
    local $limited{ $comm->id } = 1;
    is( submit_lostinfo( lostuser => 1, email_u => $email ),
        'settings/lostuser.tt', 'an over-limit community does not block the reminder' );
    is( scalar @mail, 1, 'eligible accounts still receive a reminder' );

    local $limited{ $personal->id } = 1;
    is(
        submit_lostinfo( lostuser => 1, email_u => $email ),
        '/settings/lostuser.tt.error.toofrequent',
        'personal account limits still apply'
    );
    is( scalar @mail, 0, 'over-limit personal account prevents delivery' );
};

subtest 'an email associated only with a community sends nothing' => sub {
    my $comm_email = 'community-' . $comm->id . '@example.invalid';
    $comm->set_email($comm_email);
    is(
        submit_lostinfo( lostuser => 1, email_u => $comm_email ),
        '/settings/lostuser.tt.error.no_usernames_for_email',
        'no eligible username is found'
    );
    is( scalar @mail, 0, 'community-only lookup sends no reminder' );
    is_deeply( \@rated, [], 'community-only lookup consumes no account rate limit' );
};

subtest 'password recovery still selects only permitted accounts and addresses' => sub {
    is(
        submit_lostinfo( lostpass => 1, user => $comm->user ),
        '/settings/lostpass.tt.error.commnopassword',
        'community password recovery is rejected'
    );
    is_deeply( \@actions, [], 'community rejection creates no reset token' );
    is( scalar @mail, 0, 'community rejection sends no password mail' );

    my $old_email   = 'previous-' . $personal->id . '@example.invalid';
    my $unconfirmed = 'unconfirmed-' . $personal->id . '@example.invalid';
    $personal->infohistory_add( 'email', $old_email,   'A' );
    $personal->infohistory_add( 'email', $unconfirmed, 'T' );

    for my $address ( '', $old_email ) {
        my $destination = $address || $email;
        is( submit_lostinfo( lostpass => 1, user => $personal->user, email_p => $address ),
            'settings/lostpass.tt', 'current and confirmed old recovery addresses are accepted' );
        is_deeply(
            \@actions,
            [ [ $personal->id, 'reset_password', $destination ] ],
            'reset token is bound to the personal account and selected address'
        );
        is( scalar @mail,   1,            'one reset message is captured' );
        is( $mail[0]->{to}, $destination, 'reset goes to the selected recovery address' );
        like(
            $mail[0]->{body},
            qr{/changepassword\?auth=2439\.local-test-token},
            'reset message contains the generated token link'
        );
    }

    is(
        submit_lostinfo( lostpass => 1, user => $personal->user, email_p => $unconfirmed ),
        '/settings/lostpass.tt.error.unconfirmed',
        'unconfirmed historical email is rejected'
    );
    is_deeply( \@actions, [], 'unconfirmed address creates no reset token' );
    is( scalar @mail, 0, 'unconfirmed address receives no mail' );
};

# temp_user cleans account rows, but its cleanup does not remove identitymap rows.
$dbh->do( 'DELETE FROM identitymap WHERE userid=?', undef, $identity->id );

done_testing;
