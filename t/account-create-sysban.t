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
        $dbh->do( 'DELETE FROM sysban WHERE banid = ? AND note LIKE ?', undef, $_, "$note%" )
            for @banids;
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
    my $staff = temp_user();
    $staff->grant_priv( 'sysban', 'account_create' ) or die 'Cannot grant sysban:account_create';
    LJ::set_remote($staff);
    my $modify = LJ::Sysban::modify(
        banid   => $banid,
        expire  => 0,
        bandays => 'X',
        note    => $note
    );
    LJ::set_remote(undef);
    isnt( ref $modify, 'ERROR', 'authorized staff can expire the ban' );
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

sub insert_admin_ban {
    my ( $type, $address, $label, $start, $end ) = @_;
    $dbh->do(
        'INSERT INTO sysban (what, value, note, bandate, banuntil)
          VALUES (?, ?, ?, FROM_UNIXTIME(?), FROM_UNIXTIME(?))',
        undef, $type, $address, "$note $label", $start, $end
    ) or die $dbh->errstr;
    my $banid = $dbh->{mysql_insertid};
    push @banids, $banid;
    return $banid;
}

subtest 'admin preserves existing sysban permissions' => sub {
    local $LJ::IS_DEV_SERVER              = 1;
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'sysbanAdminTest';
    local @LJ::MEMCACHE_SERVERS           = ('fake');
    my $real_memcache = LJ::MemCache::get_memcache();
    LJ::MemCache::set_memcache( LJ::Test::FakeMemCache->new );
    $request_ip = '192.0.2.1';
    my $shared_ip = '192.0.2.94';
    my $second_ip = '192.0.2.95';
    my $third_ip  = '192.0.2.97';
    my $start     = time - 60;
    my %banid     = (
        account_create =>
            insert_admin_ban( 'account_create', $shared_ip, 'registration only', $start ),
        talk_ip_test => insert_admin_ban( 'talk_ip_test', $shared_ip, 'comment CAPTCHA', $start ),
    );
    my $second_banid =
        insert_admin_ban( 'account_create', $second_ip, 'second registration', $start );
    my $third_banid = insert_admin_ban( 'account_create', $third_ip, 'third registration', $start );
    my %label       = ( account_create => 'registration only', talk_ip_test => 'comment CAPTCHA' );
    my %staff;

    for my $type ( sort keys %banid ) {
        $staff{$type} = temp_user();
        $staff{$type}->grant_priv( 'sysban', $type ) or die "Cannot grant sysban:$type";
    }
    my $wildcard = temp_user();
    $wildcard->grant_priv( 'sysban', '*' ) or die 'Cannot grant sysban:*';

    test_psgi $serve, sub {
        my ($cb) = @_;
        my $post = sub {
            my ( $user, %fields ) = @_;
            LJ::set_remote($user);
            delete $LJ::REQ_GLOBAL{form_auth_chal};
            my $token = LJ::form_auth(1);
            LJ::set_remote(undef);
            return $cb->(
                POST 'http://localhost/admin/sysban?skin=global&as=' . $user->user,
                [ lj_form_auth => $token, %fields ]
            )->content;
        };

        for my $type ( sort keys %banid ) {
            my ($other) = grep { $_ ne $type } keys %banid;
            my $user = $staff{$type};
            like(
                $post->( $user, query => 1, bantype => $type ),
                qr/\Q$note $label{$type}\E/,
                "sysban:$type can list its own bans"
            );
            like(
                $post->( $user, query => 1, bantype => $other ),
                qr/\Q$note $label{$other}\E/,
                "sysban:$type can list $other bans"
            );

            for my $include_expired ( 0, 1 ) {
                my $query = $post->(
                    $user,
                    queryone     => 1,
                    queryvalue   => $shared_ip,
                    expiredcheck => $include_expired
                );
                like(
                    $query,
                    qr/\Q$note $label{$type}\E/,
                    "sysban:$type can query its own bans (include expired: $include_expired)"
                );
                unlike(
                    $query,
                    qr/\Q$note $label{$other}\E/,
                    "sysban:$type cannot query $other notes (include expired: $include_expired)"
                );
            }

        }

        for my $type ( sort keys %banid ) {
            like(
                $post->( $wildcard, query => 1, bantype => $type ),
                qr/\Q$note $label{$type}\E/,
                "sysban:* can list $type bans"
            );
        }
        my $all = $post->( $wildcard, queryone => 1, queryvalue => $shared_ip );
        like( $all, qr/\Q$note $label{account_create}\E/, 'sysban:* can query registration bans' );
        like( $all, qr/\Q$note $label{talk_ip_test}\E/, 'sysban:* can query comment CAPTCHA bans' );

        my $new_ip = '192.0.2.98';
        like(
            $post->(
                $staff{talk_ip_test},
                add     => 1,
                bantype => 'account_create',
                value   => $new_ip,
                bandays => 7,
                note    => "$note unauthorized"
            ),
            qr/do not have the correct privileges/i,
            'adding a registration ban requires the registration ban privilege'
        );
        is(
            $dbh->selectrow_array(
                'SELECT COUNT(*) FROM sysban WHERE what = ? AND value = ? AND note = ?',
                undef, 'account_create', $new_ip, "$note unauthorized"
            ),
            0,
            'the denied add does not create a registration ban'
        );

        for my $type ( sort keys %banid ) {
            my ($other) = grep { $_ ne $type } keys %banid;
            my $updated = $post->(
                $staff{$type},
                modify  => 1,
                banid   => $banid{$other},
                expire  => 0,
                bandays => 'X',
                bantype => $type,
                note    => "$note updated $label{$other}"
            );
            like( $updated, qr/Ban modified/i, "sysban:$type can modify $other bans" );
            my $row = $dbh->selectrow_arrayref(
                'SELECT note, banuntil <= NOW() FROM sysban WHERE banid = ?',
                undef, $banid{$other} );
            is_deeply(
                $row,
                [ "$note updated $label{$other}", 1 ],
                "the $other ban is expired and its note is stored"
            );
        }

        like(
            $post->(
                $wildcard,
                modify  => 1,
                banid   => $banid{talk_ip_test},
                expire  => 0,
                bandays => 'E',
                note    => "$note updated comment CAPTCHA"
            ),
            qr/Ban modified/i,
            'sysban:* can modify a comment CAPTCHA ban'
        );
        is(
            $dbh->selectrow_array(
                'SELECT note FROM sysban WHERE banid = ?',
                undef, $banid{talk_ip_test}
            ),
            "$note updated comment CAPTCHA",
            'the note is stored'
        );

        for my $case (
            [ $second_ip, $second_banid, 'wrong type', bantype => 'talk_ip_test' ],
            [ $third_ip, $third_banid, 'no type' ],
            )
        {
            my ( $address, $id, $description, @type_field ) = @$case;
            ok(
                LJ::sysban_check( 'account_create', $address ),
                "ban is enforced before $description update"
            );
            my $cached = LJ::MemCache::get('sysban:account_create') || {};
            is( $cached->{$address}, 0, "permanent ban is cached before $description update" );
            like(
                $post->(
                    $staff{account_create},
                    modify  => 1,
                    banid   => $id,
                    expire  => 0,
                    bandays => 'X',
                    note    => "$note expired",
                    @type_field
                ),
                qr/Ban modified/i,
                "sysban:account_create can expire its own ban with $description"
            );
            ok( !LJ::sysban_check( 'account_create', $address ),
                "ban is no longer enforced immediately after $description update" );
        }
    };
    LJ::MemCache::set_memcache($real_memcache);
};

subtest 'admin lookup uses registration address equivalence and start time' => sub {
    my $now = time;
    $dbh->do("SET timestamp = $now") or die $dbh->errstr;
    my $ipv6         = '2001:db8::3294';
    my $ipv4         = '192.0.2.96';
    my $current_ipv6 = insert_admin_ban( 'account_create', $ipv6, 'current IPv6', $now );
    my $expired_ipv6 =
        insert_admin_ban( 'account_create', $ipv6, 'expired IPv6', $now - 60, $now - 1 );
    my $current_ipv4 = insert_admin_ban( 'account_create', $ipv4, 'current IPv4', $now );
    my $expired_ipv4 =
        insert_admin_ban( 'account_create', $ipv4, 'expired IPv4', $now - 60, $now - 1 );
    my $literal_id = insert_admin_ban( 'talk_ip_test', $ipv4, 'literal IPv4', $now - 60 );
    insert_admin_ban( 'account_create', $ipv4, 'future IPv4', $now + 60 );

    my $listed = LJ::Sysban::populate_full( {}, 'account_create', 20, 0 );
    is( $listed->{$ipv6}{banid}, $current_ipv6, 'type list includes a ban in its creation second' );

    for my $case (
        [ '2001:0DB8:0000:0000:0000:0000:0000:3294', $current_ipv6, $expired_ipv6 ],
        [ '::ffff:192.0.2.96',                       $current_ipv4, $expired_ipv4 ],
        )
    {
        my ( $address, $current, $expired ) = @$case;
        my $active =
            LJ::Sysban::populate_full_by_value( $address, 'account_create', 'talk_ip_test' );
        my $all = LJ::Sysban::populate_full_by_value_with_expired( $address, 'account_create',
            'talk_ip_test' );
        is_deeply( [ map { $_->{banid} } @{ $active->{account_create} // [] } ],
            [$current], "active lookup matches $address in the creation second" );
        is_deeply(
            [ sort { $a <=> $b } map { $_->{banid} } @{ $all->{account_create} // [] } ],
            [ sort { $a <=> $b } $current, $expired ],
            "include-expired lookup matches $address"
        );
        ok(
            !exists $active->{talk_ip_test} && !exists $all->{talk_ip_test},
            "other types do not match alternate spelling $address"
        );
    }

    my $literal = LJ::Sysban::populate_full_by_value( $ipv4, 'talk_ip_test' );
    is( $literal->{talk_ip_test}[0]{banid},
        $literal_id, 'other types still match their literal value' );
    ok(
        !LJ::Sysban::populate_full_by_value($ipv4),
        'a query without allowed types returns no bans'
    );
    ok(
        !LJ::Sysban::populate_full_by_value( "$ipv4\0x", 'account_create' ),
        'a malformed value does not match a valid address prefix'
    );
    $dbh->do('SET timestamp = DEFAULT') or die $dbh->errstr;
};

done_testing;
