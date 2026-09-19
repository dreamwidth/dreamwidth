#!/usr/bin/perl
#
# t/auth-session-lifecycle.t
#
# Regression tests for MFA proof lifetimes and partial session mutations.
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
use DW::Auth::TOTP;

no warnings 'redefine';
with_fake_memcache {
    my $u = temp_user();
    $u->set_password('session-test-password');
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
    my $factor      = DW::Auth::TOTP->_factor_state($u)->{factor};
    my $dbh         = LJ::get_db_writer();
    my $new_session = sub {
        my $session = LJ::Session->create( $u, exptype => 'long', nolog => 1 );
        DW::Auth::TOTP->mark_session( $u, $session, $factor );
        return $session;
    };
    my $session = $new_session->();
    my $key     = DW::Auth::TOTP->_proof_key( $u->id, $session->id );
    my $expires = time() + 60;
    $session->{timeexpire} = $expires;
    my $cache_set = \&LJ::MemCache::set;
    {
        local *LJ::MemCache::set = sub {
            if ( ref $_[0] && $_[0][1] eq $key->[1] ) {
                is( $_[1]{expires}, $expires, 'Issued proof cache records its deadline' );
                cmp_ok( $_[2], '<=', 60, 'Issued proof cache lifetime is bounded by deadline' );
                cmp_ok( $_[2], '>',  0,  'Issued proof cache has a finite positive lifetime' );
            }
            return $cache_set->(@_);
        };
        DW::Auth::TOTP->mark_session( $u, $session, $factor );
    }
    LJ::MemCache::delete($key);
    my $cache_add = \&LJ::MemCache::add;
    {
        local *LJ::MemCache::add = sub {
            if ( ref $_[0] && $_[0][1] eq $key->[1] ) {
                is( $_[1]{expires}, $expires, 'Database-loaded proof retains its deadline' );
                cmp_ok( $_[2], '<=', 60, 'Database-loaded proof cache has bounded lifetime' );
            }
            return $cache_add->(@_);
        };
        ok( $session->valid, 'Unexpired database proof validates' );
    }
    $dbh->do(
        'UPDATE mfa_sessions SET expires = ? WHERE userid = ? AND sessid = ?',
        undef, time() - 1,
        $u->id, $session->id
    );
    LJ::MemCache::set( $key, { factor => $factor, expires => time() - 1 }, 300 );
    {
        local *LJ::get_db_writer = sub { die 'Unexpected writer access' };
        ok( !$session->valid, 'Expired cached proof fails without accessing writer' );
    }
    my $destination = LJ::Session->create( $u, exptype => 'long', nolog => 1 );
    ok(
        !DW::Auth::TOTP->copy_session_proof( $u, $session, $destination ),
        'Expired proof cannot be inherited by a new session'
    );
    LJ::MemCache::delete($key);
    ok( !$session->valid, 'Expired database proof fails despite live cluster session' );
    ok( $session->_dbupdate( timeexpire => time() + 600 ), 'Cluster session can renew' );
    ok( !$session->valid, 'Renewal cannot revive expired MFA proof' );

    $session = $new_session->();
    $key     = DW::Auth::TOTP->_proof_key( $u->id, $session->id );
    $expires = time() + 90;
    ok( $session->_dbupdate( timeexpire => $expires ), 'Live proof follows expiration update' );
    is( DW::Auth::TOTP->_session_proof($session)->{expires},
        $expires, 'Expiration update discards old cached proof deadline' );
    my $cached = LJ::Session->instance( $u, $session->id );
    ok( $cached && $cached->valid, 'Warm session before failed expiration synchronization' );
    my $session_key = $session->_memkey;
    {
        local *LJ::get_db_writer = sub { die 'Central writer unavailable' };
        eval { $session->_dbupdate( timeexpire => time() - 1 ) };
        like( $@, qr/Central writer unavailable/,
            'Expiration synchronization failure is surfaced' );
    }
    ok( !LJ::MemCache::get($session_key), 'Session cache cleared despite proof update failure' );
    ok( !LJ::MemCache::get($key),         'Proof cache cleared before failed update' );
    $cached = LJ::Session->instance( $u, $session->id );
    ok( $cached && !$cached->valid, 'Next request sees shortened cluster expiration' );

    $session = $new_session->();
    $cached  = LJ::Session->instance( $u, $session->id );
    ok( $cached && $cached->valid, 'Warm session before failed proof revocation' );
    $session_key = $session->_memkey;
    {
        local *LJ::get_db_writer = sub { die 'Central writer unavailable' };
        ok( $session->destroy, 'Cluster revocation succeeds despite central cleanup failure' );
    }
    ok( LJ::MemCache::get($session_key)->{revoked}, 'Deleted session is denied in cache' );
    ok( !LJ::Session->instance( $u, $session->id ), 'Next request cannot load deleted session' );
    ok( !DW::Auth::TOTP->session_verified($session), 'Proof revocation fails closed in cache' );
};
with_fake_memcache {
    my $ordinary    = temp_user();
    my $source      = LJ::Session->create( $ordinary, exptype => 'long', nolog => 1 );
    my $destination = LJ::Session->create( $ordinary, exptype => 'long', nolog => 1 );
    ok( $source->valid, 'Ordinary session warms factor state' );
    local *LJ::get_db_writer = sub { die 'Unexpected central writer access' };
    ok( $source->_dbupdate( timeexpire => time() + 600 ), 'Ordinary renewal skips central writer' );
    ok( DW::Auth::TOTP->copy_session_proof( $ordinary, $source, $destination ),
        'Ordinary replacement skips proof lookup' );
    ok( $source->destroy, 'Ordinary deletion skips central writer' );
    ok( !LJ::Session->instance( $ordinary, $source->id ), 'Ordinary deleted session is absent' );
};
with_fake_memcache {
    my $ordinary = temp_user();
    my $session  = LJ::Session->create( $ordinary, exptype => 'long', nolog => 1 );
    LJ::MemCache::delete( [ $ordinary->id, 'mfa-factor:' . $ordinary->id ] );
    my $writes = 0;
    local *LJ::get_db_writer = sub { ++$writes; die 'Unexpected MFA cleanup' };
    ok( $session->destroy, 'Cold-cache ordinary deletion succeeds' );
    is( $writes, 0, 'Cold-cache deletion performs no central MFA cleanup' );
    ok(
        !LJ::Session->instance( $ordinary, $session->id ),
        'Cold-cache deleted session cannot be loaded'
    );
};
with_fake_memcache {
    my $account = temp_user();
    $account->set_password('marker-test-password');
    my $plain = LJ::Session->create( $account, exptype => 'long', nolog => 1 );
    ok( $plain->valid, 'Warm no-factor cache before attempted enrollment' );
    my $set                 = \&LJ::MemCache::set;
    my $reject_factor_write = sub {
        return 0 if ref $_[0] && $_[0][1] eq 'mfa-factor:' . $account->id;
        return $set->(@_);
    };
    my $secret = DW::Auth::TOTP->generate_secret;
    {
        local *LJ::MemCache::set = $reject_factor_write;
        eval { DW::Auth::TOTP->enable( $account, $secret ) };
        like(
            $@,
            qr/Unable to publish factor change marker/,
            'Failed cache marker aborts enrollment'
        );
    }
    ok( !DW::Auth::TOTP->is_enabled($account), 'Failed marker leaves factor disabled' );
    is( scalar DW::Auth::TOTP->get_recovery_codes($account),
        0, 'Failed marker installs no recovery codes' );
    ok( $plain->valid, 'Failed enrollment leaves existing ordinary session usable' );
    DW::Auth::TOTP->enable( $account, $secret );
    my @codes  = DW::Auth::TOTP->get_recovery_codes($account);
    my $proven = LJ::Session->create( $account, exptype => 'long', nolog => 1 );
    DW::Auth::TOTP->mark_session( $account, $proven,
        DW::Auth::TOTP->_factor_state($account)->{factor} );
    {
        local *LJ::MemCache::set = $reject_factor_write;
        eval { DW::Auth::TOTP->disable( $account, 'marker-test-password', $codes[0] ) };
        like( $@, qr/Unable to publish factor change marker/,
            'Failed cache marker aborts disable' );
    }
    ok( DW::Auth::TOTP->is_enabled($account), 'Failed marker retains enrolled factor' );
    ok( $proven->valid,                       'Failed disable retains verified session' );
    my @remaining = DW::Auth::TOTP->get_recovery_codes($account);
    ok( grep( { $_ eq $codes[0] } @remaining ),
        'Failed disable rolls back recovery-code consumption' );
};
with_fake_memcache {
    my $account = temp_user();
    $account->set_password('uncached-test-password');
    local @LJ::MEMCACHE_SERVERS = ();
    my $set = \&LJ::MemCache::set;
    local *LJ::MemCache::set = sub {
        return 0 if ref $_[0] && $_[0][1] eq 'mfa-factor:' . $account->id;
        return $set->(@_);
    };
    ok(
        DW::Auth::TOTP->enable( $account, DW::Auth::TOTP->generate_secret ),
        'Enrollment works when caching is explicitly unconfigured'
    );
    my @codes = DW::Auth::TOTP->get_recovery_codes($account);
    ok( DW::Auth::TOTP->disable( $account, 'uncached-test-password', $codes[0] ),
        'Disable works when caching is explicitly unconfigured' );
};

{
    my $account = temp_user();
    my $other   = temp_user();
    DW::Auth::TOTP->enable( $account, DW::Auth::TOTP->generate_secret );
    my $dbh = LJ::get_db_writer();
    for my $owner ( $account, $other ) {
        $dbh->do( 'REPLACE INTO mfa_sessions (userid, sessid, factor, expires) VALUES (?, ?, ?, ?)',
            undef, $owner->id, 99999, 'expired-proof', time() - 1 );
    }
    my $session = LJ::Session->create( $account, exptype => 'long', nolog => 1 );
    DW::Auth::TOTP->mark_session( $account, $session,
        DW::Auth::TOTP->_factor_state($account)->{factor} );
    my ($own) = $dbh->selectrow_array(
        'SELECT COUNT(*) FROM mfa_sessions WHERE userid = ? AND sessid = 99999',
        undef, $account->id );
    my ($unrelated) = $dbh->selectrow_array(
        'SELECT COUNT(*) FROM mfa_sessions WHERE userid = ? AND sessid = 99999',
        undef, $other->id );
    is( $own,       0, 'Proof creation cleans only this account expired rows' );
    is( $unrelated, 1, 'Proof creation leaves unrelated accounts alone' );
}
with_fake_memcache {
    my $u = temp_user();
    DW::Auth::TOTP->enable( $u, DW::Auth::TOTP->generate_secret );
    my $session = LJ::Session->create( $u, exptype => 'long', nolog => 1 );
    DW::Auth::TOTP->mark_session( $u, $session, DW::Auth::TOTP->_factor_state($u)->{factor} );
    ok( LJ::Session->instance( $u, $session->id )->valid, 'Warm live session and proof caches' );
    my $proofkey = DW::Auth::TOTP->_proof_key( $u->id, $session->id );
    my $set      = \&LJ::MemCache::set;
    {
        local *LJ::MemCache::set = sub {
            return 0 if ref $_[0] && $_[0][1] eq $proofkey->[1] && !$_[1]{factor};
            $set->(@_);
        };
        eval { $session->destroy };
        like(
            $@,
            qr/Unable to publish MFA session revocation/,
            'Failed proof denial aborts logout'
        );
    }
    ok( LJ::Session->instance( $u, $session->id )->valid, 'Failed logout retains usable session' );
    is(
        $u->selectrow_array(
            'SELECT COUNT(*) FROM sessions WHERE userid=? AND sessid=?', undef,
            $u->id,                                                      $session->id
        ),
        1,
        'Failed proof marker leaves authoritative cluster row intact'
    );
    {
        local *LJ::MemCache::delete = sub { 0 };
        ok( $session->destroy, 'Logout succeeds despite cache-delete failure' );
    }
    ok( !LJ::Session->instance( $u, $session->id ), 'Session denial defeats stale positive cache' );
    ok( !$session->valid, 'Proof denial also rejects an already-loaded session' );
};
with_fake_memcache {
    my $u       = temp_user();
    my $session = LJ::Session->create( $u, exptype => 'long', nolog => 1 );
    LJ::Session->instance( $u, $session->id );
    my $set = \&LJ::MemCache::set;
    {
        local *LJ::MemCache::set = sub {
            return 0 if ref $_[0] && $_[0][1] eq $session->_memkey->[1] && $_[1]{revoked};
            $set->(@_);
        };
        eval { $session->destroy };
        like(
            $@,
            qr/Unable to publish session revocation/,
            'Ordinary session marker failure is not silent'
        );
    }
    is(
        $u->selectrow_array(
            'SELECT COUNT(*) FROM sessions WHERE userid=? AND sessid=?', undef,
            $u->id,                                                      $session->id
        ),
        1,
        'Session marker failure retains authoritative row'
    );
    {
        my $do = \&LJ::User::do;
        local *LJ::User::do = sub { return 0 if $_[1] =~ /^DELETE FROM sessions WHERE/; $do->(@_) };
        eval { $session->destroy };
        like(
            $@,
            qr/Unable to delete account sessions/,
            'Database deletion failure is not reported as successful logout'
        );
    }
    ok( $session->destroy, 'Failed revocation can be retried' );
};
{
    my $u       = temp_user();
    my $session = LJ::Session->create( $u, exptype => 'long', nolog => 1 );
    {
        local *DW::Locker::trylock = sub { undef };
        eval { $session->destroy };
        like(
            $@,
            qr/Unable to lock account sessions/,
            'Lock acquisition failure aborts session deletion'
        );
    }
    ok( LJ::Session->instance( $u, $session->id ), 'Lock failure retains authoritative session' );
}
done_testing();
