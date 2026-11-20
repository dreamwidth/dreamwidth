#!/usr/bin/perl
# t/account-create-sysban.t
#
# Tests registration-only IP bans through the Plack application.
#
# Authors:
#      Alex <saphid@users.noreply.github.com>
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

use LJ::MemCache;
use LJ::Sysban;
use LJ::Console;
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die "Failed to load app.psgi: $@ $!" unless ref $app eq 'CODE';

my $dbh  = LJ::get_db_writer();
my $ip   = '2001:db8::3293';
my $note = 't/account-create-sysban.t';
my @banids;

END {
    if (@banids) {
        $dbh->do( 'DELETE FROM sysban WHERE banid = ? AND note = ?', undef, $_, $note ) for @banids;
        LJ::MemCache::delete('sysban:account_create');
    }
}

my $request_ip;
my $serve = sub {
    my ($env) = @_;
    $env->{REMOTE_ADDR} = $request_ip;
    return $app->($env);
};

local $LJ::USE_ACCT_CODES  = 0;
local $LJ::TRUST_X_HEADERS = 0;
my $create_link = qr{href\s*=\s*["'](?:https?://[^/"']+)?/create/?["']}i;
my $blocked     = qr/you cannot use it to create a Dreamwidth account/i;

test_psgi $serve, sub {
    my ($cb) = @_;
    $request_ip = $ip;

    my $create = $cb->( GET 'http://localhost/create?skin=global' );
    is( $create->code, 200, 'unbanned IP can load registration' );
    like( $create->content, qr/id=["']js-user["']/, 'unbanned IP sees the registration form' );
    like( $cb->( GET 'http://localhost/?skin=global' )->content,
        $create_link, 'homepage advertises registration before the ban' );
    like( $cb->( GET 'http://localhost/nav/create?skin=global' )->content,
        $create_link, 'navigation advertises registration before the ban' );

    $dbh->do(
'INSERT INTO sysban (what, value, note, bandate) VALUES (?, ?, ?, NOW() - INTERVAL 1 SECOND)',
        undef, 'account_create', $ip, $note
    );
    my $banid = $dbh->{mysql_insertid};
    push @banids, $banid;
    LJ::MemCache::delete('sysban:account_create');

    $request_ip = '2001:0DB8:0000:0000:0000:0000:0000:3293';
    for my $request (
        GET('http://localhost/create?skin=global'),
        POST( 'http://localhost/create?skin=global', [ user => 'dwregression3293' ] ),
        )
    {
        $request->header( 'X-Forwarded-For' => '192.0.2.1' );
        my $response = $cb->($request);
        is( $response->code, 403, $request->method . ' /create refuses the banned connection' );
        like( $response->content, $blocked, 'refusal explains the registration ban' );
        unlike( $response->content, qr/id=["']js-user["']/, 'no registration form is returned' );
    }

    my $home = $cb->( GET 'http://localhost/?skin=global' );
    is( $home->code, 200, 'banned IP can still view the homepage' );
    unlike( $home->content, $create_link, 'homepage hides registration links' );
    unlike( $home->content, qr{href=["'][^"']*/account\?for=new}, 'no paid signup link either' );

    my $menu = $cb->( GET 'http://localhost/nav/create?skin=global' );
    is( $menu->code, 200, 'banned IP can still view the Create menu' );
    unlike( $menu->content, $create_link, 'navigation hides the registration link' );
    like( $menu->content, qr{/manage/settings/}, 'other anonymous navigation remains available' );

    $request_ip = '192.0.2.1';
    my $unrelated_request = GET 'http://localhost/create?skin=global';
    $unrelated_request->header( 'X-Forwarded-For' => $ip );
    is( $cb->($unrelated_request)->code,
        200, 'an unrelated IP can still register while the ban is active' );

    $request_ip = $ip;
    LJ::Sysban::modify(
        banid   => $banid,
        expire  => 0,
        bandays => 'X',
        what    => 'account_create',
        value   => $ip,
        note    => $note
    );
    is( $cb->( GET 'http://localhost/create?skin=global' )->code,
        200, 'expiring a cached ban restores access to registration' );
};

subtest 'registration ban privilege and console command' => sub {
    ok( grep( $_ eq 'account_create', LJ::list_valid_args('sysban') ),
        'account_create is available for sysban privilege grants and in the admin menu' );

    my $user = temp_user();
    LJ::set_remote($user);
    local $LJ::T_NO_COMMAND_PRINT = 1;
    my $run = sub { return LJ::Console->run_commands_text(shift); };
    $user->grant_priv( 'sysban', 'ip' );
    like(
        $run->("sysban_add account_create 192.0.2.93 0 $note"),
        qr/cannot create these ban types/i,
        'the general IP privilege is not sufficient'
    );

    $user->grant_priv( 'sysban', 'account_create' );
    like(
        $run->("sysban_add account_create 192.0.2.999 0 $note"),
        qr/valid IPv4 or IPv6/,
        'invalid IP octets are rejected'
    );
    like(
        $run->("sysban_add account_create 192.0.2.0/24 0 $note"),
        qr/valid IPv4 or IPv6/,
        'CIDR is not accepted as an individual IP'
    );

    local %LJ::UNBANNABLE_IPS = ( '^192\.0\.2\.42$' => 'protected by test' );
    like(
        $run->("sysban_add account_create ::ffff:192.0.2.42 0 $note"),
        qr/Cannot ban IP.*protected by test/,
        'protected IPs are still protected'
    );

    my $result = $run->("sysban_add account_create ::ffff:192.0.2.93 0 $note");
    like( $result, qr/Successfully created ban #(\d+)/, 'console accepts a permanent ban' );
    if ( my ($banid) = $result =~ /#(\d+)/ ) {
        push @banids, $banid;
    }

    ok( LJ::sysban_check( 'account_create', '192.0.2.93' ),
        'a permanent IPv4-mapped ban is immediately active for the IPv4 address' );
    ok( !LJ::sysban_check( 'ip', '192.0.2.93' ), 'registration ban does not create an IP ban' );
    like(
        $run->("sysban_add account_create 192.0.2.93 7 $note"),
        qr/already banned/i,
        'equivalent IP spellings cannot create duplicate active bans'
    );
    LJ::set_remote(undef);
};

done_testing;
