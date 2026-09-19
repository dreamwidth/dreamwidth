#!/usr/bin/perl
#
# DW::API::Key
#
# Defines API Key objects and provides helper functions for checking them
# and the permissions they have, for use with DW::Controller::API::REST endpoints.
#
# TODO: Many of the helper functions are stubs, to be filled out when we implement API key scoping
# Authors:
#      Ruth Hatch <ruth.s.hatch@gmail.com>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::API::Key;

use strict;
use warnings;
use Carp;
use Digest::MD5 ();

use LJ::Utils;

# Usage: new_for_user ( user )
# Creates a new API key for a given user, saves it to DB,
# and returns the new key object.
sub new_for_user {
    my ( $self, $u ) = @_;
    my $user = LJ::want_user($u)
        or croak "need a user!\n";

    my $id = LJ::alloc_user_counter( $user, 'B' )
        or croak 'Unable to allocate user counter for API key.';

    my $key = LJ::rand_chars(32);
    my $dbw = LJ::get_db_writer() or croak "Failed to get database";
    $dbw->do(
        q{INSERT INTO api_key (userid, keyid, hash, state)
         VALUES (?, ?, ?, 'A')},
        undef, $user->id, $id, $key
    );

    if ( $dbw->err ) {
        carp "Failed to insert key row: " . $dbw->errstr . ".";
        return undef;
    }

    return $self->_create( $user, $id, $key );
}

# Protocol clients authenticate with a key, never the account password.
sub authenticate {
    my ( $class, $u, $credential, %opts ) = @_;
    return 0
        unless $u
        && $u->is_person
        && defined $credential
        && !$u->is_locked
        && !$u->is_memorial
        && !$u->is_expunged;
    return 0 if LJ::login_ip_banned($u);
    my $key = $class->get_key($credential);
    return 1 if $key && $key->valid_for_user($u);
    if ( $opts{allow_hpassword} ) {
        for my $candidate ( @{ $class->get_keys_for_user($u) || [] } ) {
            return 1 if $credential eq Digest::MD5::md5_hex( $candidate->hash );
        }
    }
    LJ::handle_bad_login($u);
    return 0;
}

sub _cache_key { return 'api-key-v2:' . $_[1] }

# Look up an active key by its secret, or return undef.
sub get_key {
    my ( $class, $hash ) = @_;
    return undef unless $hash;
    my $memkey = $class->_cache_key($hash);
    my $cached = LJ::MemCache::get($memkey);
    unless ( defined $cached ) {
        my $dbh             = LJ::get_db_writer() or croak 'Failed to get database';
        my $own_transaction = $dbh->{AutoCommit};
        my $loaded          = eval {
            $dbh->begin_work or die $dbh->errstr if $own_transaction;
            my $row = $dbh->selectrow_hashref(
                "SELECT keyid, userid, hash, state FROM api_key WHERE hash = ? FOR UPDATE",
                undef, $hash );
            die $dbh->errstr if $dbh->err;
            $cached = $row && $row->{state} eq 'A' ? { key => $row } : { revoked => 1 };
            if ($own_transaction) {

                # Serialize cache fills with revocation; never replace a tombstone.
                LJ::MemCache::add( $memkey, $cached, 86400 );
                $cached = LJ::MemCache::get($memkey) || $cached;
                $dbh->commit or die $dbh->errstr;
            }
            1;
        };
        unless ($loaded) {
            my $error = $@;
            $dbh->rollback if $own_transaction && !$dbh->{AutoCommit};
            die $error;
        }
    }
    return undef if $cached->{revoked} || !$cached->{key};
    my $row  = $cached->{key};
    my $user = LJ::want_user( $row->{userid} ) or return undef;
    return $class->_create( $user, $row->{keyid}, $row->{hash} );
}

# Usage: get_keys_for_user ( user )
# Looks up all API keys for a given user. Returns an arrayef of key objects,
# or undef if the user has no API keys yet.
sub get_keys_for_user {
    my ( $self, $u ) = @_;
    my $user = LJ::want_user($u)
        or croak "need a user!\n";
    my @keylist;

    my $dbh  = LJ::get_db_writer() or croak "Failed to get database";
    my $keys = $dbh->selectall_hashref(
        q{SELECT keyid, hash FROM api_key WHERE userid = ? AND state = 'A'},
        'keyid', undef, $user->{userid} );
    carp $dbh->errstr if $dbh->err;
    return undef unless $keys;

    for my $key ( sort ( keys %$keys ) ) {
        my $new = $self->_create( $user, $keys->{$key}->{keyid}, $keys->{$key}->{hash} );
        push @keylist, $new;
    }

    # sort oldest to newest (predictable ordering for management page)
    return [ sort { $a->{keyid} <=> $b->{keyid} } @keylist ];
}

# Usage: create ( user, key )
# Creates and returns a new key object given a user and key hash.
# Don't call this directly, as it neither verifies nor saves keys.
# new_for_user() or get_key() is probably what you want instead.
sub _create {
    my ( $class, $user, $keyid, $keyhash ) = @_;

    my %key = (
        user    => $user,
        keyid   => $keyid,
        keyhash => $keyhash
    );

    bless \%key, $class;
    return \%key;
}

# Usage: $key->can_read( resource )
# Checks if a key has been given read permissions
# for a given resource by the user it belongs to.

sub can_read {
    my ( $self, $resource ) = @_;

    #TODO: Once key scoping is implemented, actually check this
    return 1;
}

# Usage: $key->can_write( resource )
# Checks if a key has been given write permissions
# for a given resource by the user it belongs to.

sub can_write {
    my ( $self, $resource ) = @_;

    #TODO: Once key scoping is implemented, actually check this
    return 1;
}

# Usage: $key->delete ($user)
# Marks a key as deleted in the DB. A user is required to guarantee
# that the key is being deleted by someone with the permission to do so.
sub delete {
    my ( $self, $u ) = @_;
    my $user = LJ::want_user($u)
        or croak "need a user!\n";

    $self->valid_for_user($user) or croak "key doesn't belong to user";
    my $memkey          = $self->_cache_key( $self->{keyhash} );
    my $dbw             = LJ::get_db_writer() or croak 'Failed to get database';
    my $own_transaction = $dbw->{AutoCommit};
    my $deleted         = eval {
        $dbw->begin_work or die $dbw->errstr if $own_transaction;
        $dbw->selectrow_array( 'SELECT keyid FROM api_key WHERE hash = ? FOR UPDATE',
            undef, $self->{keyhash} );
        die $dbw->errstr if $dbw->err;

        # Publish denial before changing the database. A failed cache write must
        # not report successful revocation while an old positive entry survives.
        if (@LJ::MEMCACHE_SERVERS) {
            LJ::MemCache::set( $memkey, { revoked => 1 }, 86400 )
                or die 'Unable to publish API-key revocation';
        }
        $dbw->do( "UPDATE api_key SET state = 'D' WHERE state = 'A' AND hash = ?",
            undef, $self->{keyhash} )
            or die $dbw->errstr;
        $dbw->commit or die $dbw->errstr if $own_transaction;
        1;
    };
    unless ($deleted) {
        my $error = $@;
        $dbw->rollback if $own_transaction && !$dbw->{AutoCommit};
        die $error;
    }
    return 1;
}

sub valid_for_user {
    my ( $self, $u ) = @_;
    return $self->{user}->equals($u);
}

sub hash {

    # Returns the "key" itself, or the hash of it
    return $_[0]->{keyhash};
}

# Usage: get_one (user)
# Given a user, either return the first found key for them, or
# if they have no keys yet, generate one. Intended for use in
# situations where we have a logged in user and want to get a working API
# key for them, without forcing them to jump through the menu hoops themselves.
sub get_one {
    my ( $self, $u ) = @_;
    my $apikeys = $self->get_keys_for_user($u);
    my $key;

    if ( defined( $apikeys->[0] ) ) {
        $key = $apikeys->[0];
    }
    else {
        $key = $self->new_for_user($u);
    }
    return $key;
}

1;
