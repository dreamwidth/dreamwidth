#!/usr/bin/perl
#
# t/auth-api-key.t
#
# Regression tests for API-key cache publication and revocation.
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
use DW::API::Key;
no warnings 'redefine';
with_fake_memcache {
    my $u        = temp_user();
    my $key      = DW::API::Key->new_for_user($u);
    my $cachekey = DW::API::Key->_cache_key( $key->hash );
    ok( DW::API::Key->authenticate( $u, $key->hash ), 'Warm positive key cache' );
    {
        my $set = \&LJ::MemCache::set;
        local *LJ::MemCache::set = sub {
            return 0 if $_[0] eq $cachekey && $_[1]{revoked};
            $set->(@_);
        };
        eval { $key->delete($u) };
        like(
            $@,
            qr/Unable to publish API-key revocation/,
            'Failed denial marker aborts revocation'
        );
    }
    my $dbh = LJ::get_db_writer();
    my ($state) =
        $dbh->selectrow_array( 'SELECT state FROM api_key WHERE hash = ?', undef, $key->hash );
    is( $state, 'A', 'Failed revocation does not claim a database revocation' );
    {
        my $set = \&LJ::MemCache::set;
        local *LJ::MemCache::set = sub {
            if ( $_[0] eq $cachekey && $_[1]{revoked} ) {
                ok( !$dbh->{AutoCommit}, 'Denial marker published under key lock' );
                my ($state) = $dbh->selectrow_array( 'SELECT state FROM api_key WHERE hash = ?',
                    undef, $key->hash );
                is( $state, 'A', 'Denial marker precedes database revocation' );
            }
            $set->(@_);
        };
        local *LJ::MemCache::delete = sub { 0 };
        ok( $key->delete($u), 'Revocation does not depend on a later cache deletion' );
        ok(
            !DW::API::Key->authenticate( $u, $key->hash ),
            'Revoked key fails despite cache-delete failure'
        );
    }
    LJ::MemCache::delete($cachekey);
    LJ::MemCache::set( 'api_key:' . $key->hash,
        { userid => $u->id, keyid => 1, hash => $key->hash }, 86400 );
    ok(
        !DW::API::Key->authenticate( $u, $key->hash ),
        'Old unversioned positive cache cannot revive revoked key'
    );
};
with_fake_memcache {
    my $u        = temp_user();
    my $key      = DW::API::Key->new_for_user($u);
    my $cachekey = DW::API::Key->_cache_key( $key->hash );
    my $add      = \&LJ::MemCache::add;
    my $raced;
    local *LJ::MemCache::add = sub {
        if ( $_[0] eq $cachekey && !$raced++ ) {
            ok( !LJ::get_db_writer()->{AutoCommit}, 'Cache fill holds the key lock' );
            $key->delete($u);
        }
        $add->(@_);
    };
    ok( !DW::API::Key->get_key( $key->hash ),
        'Delayed positive fill cannot replace revocation tombstone' );
    ok( LJ::MemCache::get($cachekey)->{revoked}, 'Revocation tombstone remains authoritative' );
};
done_testing();
