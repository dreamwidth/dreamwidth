#!/usr/bin/perl
# t/sysban-admin.t
#
# Tests IP ban administration against the database.
#
# Authors:
#      Dreamwidth Studios, LLC.
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
use Cache::Memcached;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Sysban;
use LJ::Test qw(temp_user with_fake_memcache);

my $shared_cache = $ENV{DW_TEST_SYSBAN_MEMCACHE};
if ($shared_cache) {
    $ENV{DW_TEST_SYSBAN_CACHE_NAMESPACE} //= "dw-test-sysban:$$:";
    LJ::MemCache::set_memcache(
        Cache::Memcached->new(
            { servers => [$shared_cache], namespace => $ENV{DW_TEST_SYSBAN_CACHE_NAMESPACE} }
        )
    );
}

if ( @ARGV && $ARGV[0] eq '--operator-script' ) {
    shift @ARGV;
    do "$ENV{LJHOME}/bin/ljsysban.pl";
    die $@ || $!;
}

my $dbh = LJ::get_db_writer();
my ( @banids, @srids );

END {
    if ($dbh) {
        $dbh->do( 'DELETE FROM spamreports WHERE srid = ?', undef, $_ ) for @srids;
        $dbh->do( 'DELETE FROM sysban WHERE banid = ?',     undef, $_ ) for @banids;
        LJ::Sysban::ban_do($_) for qw(ip noanon_ip);
    }
}

sub seed_ban {
    my ( $type, $value, $note ) = @_;
    $dbh->do(
        'INSERT INTO sysban (what, value, bandate, note) VALUES (?, ?, NOW() - INTERVAL 1 DAY, ?)',
        undef, $type, $value, $note
    ) or die $dbh->errstr;
    my $banid = $dbh->{mysql_insertid};
    push @banids, $banid;
    LJ::Sysban::ban_do($type);
    return $banid;
}

sub sysban_cli {
    open my $output, '-|', $^X, __FILE__, '--operator-script', @_ or die $!;
    my $text = do { local $/; <$output> }
        // '';
    my $success = close $output;
    return ( $success, $text );
}

subtest 'Native and mapped IPv4 resolve to the same IP ban' => sub {
    with_fake_memcache {
        for my $type (qw(ip noanon_ip talk_ip_test)) {
            my $ipv4       = '192.0.2.210';
            my $mapped     = '::ffff:192.0.2.210';
            my $mapped_hex = '::ffff:c000:2d2';
            my $compatible = '::192.0.2.210';
            my $banid      = seed_ban( $type, $mapped_hex, 'mapped legacy row' );
            my $literal_id = seed_ban( 'uniq', $mapped_hex, 'non-IP literal row' );

            for my $stored ( $mapped_hex, $mapped, $ipv4 ) {
                $dbh->do( 'UPDATE sysban SET value = ? WHERE banid = ?', undef, $stored, $banid );
                LJ::Sysban::ban_do($type);
                for my $input ( $ipv4, $mapped, $mapped_hex ) {
                    my $label = "$type: $input matches $stored";
                    ok( LJ::sysban_check( $type, $input ), "$label for enforcement" );
                    like(
                        LJ::Sysban::validate( $type, $input ) // '',
                        qr/already banned/,
                        "$label for duplicate detection"
                    );
                    my $result = LJ::Sysban::populate_full_by_value( $input, $type );
                    is_deeply( [ map { $_->{banid} } @{ $result->{$type} // [] } ],
                        [$banid], "$label for admin lookup" );
                }
            }

            ok( !LJ::sysban_check( $type, $compatible ), "$type: compatible IPv6 is distinct" );
            my $result = LJ::Sysban::populate_full_by_value( $ipv4, 'uniq' );
            ok( !$result, 'Non-IP bans still use literal matching' );

            $dbh->do( 'UPDATE sysban SET value = ? WHERE banid = ?', undef, $mapped_hex, $banid );
            my ( $listed, $output ) = sysban_cli( '--list', '--what', $type, '--value', $ipv4 );
            ok( $listed, 'Operator lookup succeeds' );
            like( $output, qr/banid: \Q$banid\E,/, 'Operator lookup finds the legacy mapped row' );

            $dbh->do( 'UPDATE sysban SET banuntil = NOW() - INTERVAL 1 DAY WHERE banid = ?',
                undef, $banid );
            my $active = LJ::Sysban::populate_full_by_value( $ipv4, $type );
            ok( !$active, 'Active lookup excludes the expired row' );
            my $expired = LJ::Sysban::populate_full_by_value_with_expired( $ipv4, $type );
            is_deeply( [ map { $_->{banid} } @{ $expired->{$type} // [] } ],
                [$banid], 'Expired lookup returns the same ban ID' );

            $dbh->do( 'DELETE FROM sysban WHERE banid IN (?, ?)', undef, $banid, $literal_id );
            LJ::Sysban::ban_do($type);
        }
    };
};

subtest 'Legacy zero-padded IPv4 rows use decimal octets' => sub {
    with_fake_memcache {
        my $ipv4   = '192.0.2.10';
        my $padded = '192.000.002.010';
        for my $type (qw(ip noanon_ip talk_ip_test)) {
            for my $stored ( $padded, "::ffff:$padded" ) {
                my $banid = seed_ban( $type, $stored, 'zero-padded legacy row' );
                my $label = "$type: $stored";

                ok( LJ::sysban_check( $type, $ipv4 ),   "$label enforces the decimal address" );
                ok( LJ::sysban_check( $type, $padded ), "$label enforces the padded spelling" );
                like(
                    LJ::Sysban::validate( $type, $ipv4 ) // '',
                    qr/already banned/,
                    "$label prevents a duplicate"
                );
                my $result = LJ::Sysban::populate_full_by_value( $ipv4, $type );
                is_deeply( [ map { $_->{banid} } @{ $result->{$type} // [] } ],
                    [$banid], "$label is found by admin lookup" );

                $dbh->do( 'DELETE FROM sysban WHERE banid = ?', undef, $banid );
                LJ::Sysban::ban_do($type);
            }
        }
    };
};

subtest 'Operator rejects blank replacement values without expiring the ban' => sub {
    my $ipv4  = '192.0.2.10';
    my $banid = seed_ban( 'ip', $ipv4, 'blank replacement test' );
    for my $replacement ( " \t ", '' ) {
        my ( $modified, $output ) =
            sysban_cli( '--modify', '--banid', $banid, '--value', $replacement,
            '--banuntil', '2000-01-01 00:00:00',
            );
        ok( !$modified, 'Operator rejects the blank replacement' );
        my $row = $dbh->selectrow_arrayref( 'SELECT value, banuntil FROM sysban WHERE banid = ?',
            undef, $banid );
        is_deeply( $row, [ $ipv4, undef ], 'Neither the address nor the expiry changes' );
    }
};

subtest 'Operator normalizes padded writes and handles equivalent edits' => sub {
    my $note = 'operator normalization test';
    my ( $added, $output ) = sysban_cli(
        '--add',                 '--what',   'talk_ip_test', '--value',
        " \t2001:0DB8::0210\t ", '--status', 'active',       '--bandate',
        '2000-01-01 00:00:00',   '--note',   $note,
    );
    ok( $added, 'Operator add succeeds' );
    my ($banid) = $output =~ /CREATED: banid=(\d+)/;
    ok( $banid, 'Operator reports the new ban ID' ) or return;
    push @banids, $banid;
    my $value = sub {
        return $dbh->selectrow_array( 'SELECT value FROM sysban WHERE banid = ?', undef, $banid );
    };
    is( $value->(), '2001:db8::210', 'Operator stores an unpadded canonical IPv6 address' );

    my ( $modified, $changed ) =
        sysban_cli( '--modify', '--banid', $banid, '--value', " \t2001:0DB8::0211\t " );
    ok( $modified, 'Operator modify succeeds' );
    like( $changed, qr/^MODIFIED:/m, 'Operator reports a changed address' );
    is( $value->(), '2001:db8::211', 'Operator modify stores an unpadded canonical address' );
    ok( LJ::sysban_check( 'talk_ip_test', '2001:db8::211' ), 'The modified address is enforced' );

    $dbh->do( 'UPDATE sysban SET value = ? WHERE banid = ?', undef, '2001:db8::211', $banid );
    my ( $listed, $matches ) = sysban_cli( '--list', '--value', " \t2001:0DB8::0211\t " );
    ok( $listed, 'Operator list succeeds' );
    like( $matches, qr/banid: \Q$banid\E,/, 'Operator lookup accepts a padded address' );

    my $modifications = sub {
        return $dbh->selectrow_array(
            "SELECT COUNT(*) FROM statushistory WHERE shtype = 'sysban_mod' AND notes LIKE ?",
            undef, "banid=$banid;%note=$note;%" );
    };
    my $before = $modifications->();
    my ( $success, $unchanged ) =
        sysban_cli( '--modify', '--banid', $banid, '--value', '2001:0DB8::0211' );
    ok( $success, 'An equivalent edit exits successfully' );
    unlike( $unchanged, qr/^MODIFIED:/m, 'An equivalent edit does not report a modification' );
    is( $value->(),         '2001:db8::211', 'An equivalent edit does not change the row' );
    is( $modifications->(), $before,         'An equivalent edit does not log a modification' );
};

subtest 'Operator type edits invalidate both warm shared caches' => sub {
    my $value = '2001:db8::212';
    my $banid = seed_ban( 'ip', $value, 'operator type edit test' );
    LJ::Sysban::ban_do('noanon_ip');
    ok( LJ::sysban_check( 'ip', $value ), 'Old type is banned before the edit' );
    ok( !LJ::sysban_check( 'noanon_ip', $value ), 'New type is not banned before the edit' );
SKIP: {
        skip 'Set DW_TEST_SYSBAN_MEMCACHE to test cross-process invalidation', 5
            unless $shared_cache;
        ok( LJ::MemCache::get('sysban:ip') && LJ::MemCache::get('sysban:noanon_ip'),
            'Both shared caches are warm' );
        my ( $success, $output ) =
            sysban_cli( '--modify', '--banid', $banid, '--what', 'noanon_ip' );
        ok( $success, 'Operator type edit succeeds' );
        like( $output, qr/^MODIFIED:/m, 'Operator reports the type change' );
        local $LJ::IP_BANNED_LOADED        = 0;
        local $LJ::NOANON_IP_BANNED_LOADED = 0;
        ok( !LJ::sysban_check( 'ip', $value ), 'Old type reloads without the ban' );
        ok( LJ::sysban_check( 'noanon_ip', $value ), 'New type reloads with the ban' );
    }
};

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'sysbanAdminTest';
my $admin = temp_user();
$admin->grant_priv( 'siteadmin', 'spamreports' );
$admin->grant_priv( 'sysban',    '*' );

with_fake_memcache {
    test_psgi $app, sub {
        my ($request) = @_;
        my $post = sub {
            my ( $path, @fields ) = @_;
            LJ::set_remote($admin);
            delete $LJ::REQ_GLOBAL{form_auth_chal};
            my $auth = LJ::form_auth(1);
            LJ::set_remote(undef);
            return $request->(
                POST 'http://localhost/admin/' . $path . '?as=' . $admin->user,
                Content => [ lj_form_auth => $auth, @fields ],
            );
        };

        subtest 'Web lookup trims input and web expiry invalidates the saved type' => sub {
            my $address = '2001:db8::213';
            my $note    = 'web query match marker';
            my $banid   = seed_ban( 'ip', $address, $note );
            my $result  = $post->( 'sysban', queryone => 1, queryvalue => " \t2001:0DB8::0213\t " );
            ok( $result->decoded_content =~ /\Q$note\E/, 'Web lookup finds a padded IPv6 query' );

            ok( LJ::sysban_check( 'ip', $address ), 'The ban is warm before expiry' );
            $post->(
                'sysban',
                modify  => 1,
                banid   => $banid,
                expire  => 0,
                bandays => 'X',
                note    => $note,
                bantype => 'noanon_ip',
                value   => $address
            );
            my $active = LJ::Sysban::populate_full_by_value( $address, 'ip' );
            ok( !$active, 'Web modification expires the row in the database' );
            ok( !LJ::sysban_check( 'ip', $address ),
                'Web modification invalidates the warm cache' );
        };

        subtest 'Spam Reports closes reports but only creates IPv4 bans' => sub {
            for my $case ( [ '192.0.2.214', 1 ], [ '2001:db8::214', 0 ],
                [ '::ffff:192.0.2.215', 0 ] )
            {
                my ( $address, $expect_ban ) = @$case;
                my $note = "spam report for $address";
                $dbh->do(
                    "INSERT INTO spamreports (reporttime, posttime, ip, journalid, body) "
                        . "VALUES (UNIX_TIMESTAMP(), UNIX_TIMESTAMP(), ?, ?, '')",
                    undef, $address, $admin->id
                ) or die $dbh->errstr;
                my $srid = $dbh->{mysql_insertid};
                push @srids, $srid;

                $post->(
                    'spamreports',
                    mode        => 'del',
                    srids       => $srid,
                    sysban_ip   => $address,
                    sysban_note => $note,
                    ret         => '/admin/spamreports'
                );
                is(
                    $dbh->selectrow_array(
                        'SELECT state FROM spamreports WHERE srid = ?',
                        undef, $srid
                    ),
                    'closed',
                    "$address: report is closed"
                );
                my $bans = $dbh->selectcol_arrayref(
                    "SELECT banid FROM sysban WHERE what = 'talk_ip_test' AND note = ?",
                    undef, $note );
                push @banids, @$bans;
                is( scalar @$bans, $expect_ban, "$address: shortcut only bans native IPv4" );
            }
        };
    };
};

done_testing();
