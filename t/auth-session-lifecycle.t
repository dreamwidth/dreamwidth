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
    ok( !LJ::MemCache::get($session_key), 'Deleted session cannot remain in cache' );
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
done_testing();
