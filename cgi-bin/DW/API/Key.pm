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

    # with a new key added, our cached api_keys_list for the user is out of date
    LJ::MemCache::delete( [ $user->id, "api_keys_list:" . $user->id ] );

    return $self->_create( $user, $id, $key );
}

# Usage: lookup ( user, key )
# Looks for a given key for a user. Returns the key object
# if it's valid, or undef otherwise.
sub get_key {
    my ( $class, $hash ) = @_;

    return undef unless $hash;
    my $memkey  = [ $hash, "api_key:" . $hash ];
    my $keydata = LJ::MemCache::get($memkey);

    unless ( defined $keydata ) {
        my $dbr = LJ::get_db_reader() or croak "Failed to get database";
        $keydata = $dbr->selectrow_hashref(
            "SELECT keyid, userid, hash FROM api_key WHERE hash = ? AND state = 'A'",
            undef, $hash );
        carp $dbr->errstr if $dbr->err;
        LJ::MemCache::set( $memkey, $keydata );
    }

    if ($keydata) {
        my $user = LJ::want_user( $keydata->{userid} );
        return $class->_create( $user, $keydata->{keyid}, $keydata->{hash} );
    }
    else {
        return undef;
    }
}

# Usage: get_keys_for_user ( user )
# Looks up all API keys for a given user. Returns an arrayef of key objects,
# or undef if the user has no API keys yet.
sub get_keys_for_user {
    my ( $self, $u ) = @_;
    my $user = LJ::want_user($u)
        or croak "need a user!\n";
    my $memkey  = [ $user->id, "api_keys_list:" . $user->id ];
    my $keydata = LJ::MemCache::get($memkey);
    my @keylist;

    if ( defined $keydata ) {
        for my $keyhash (@$keydata) {
            push @keylist, ( $self->get_key($keyhash) );
        }

    }
    else {
        my $dbr  = LJ::get_db_reader() or croak "Failed to get database";
        my $keys = $dbr->selectall_hashref(
            q{SELECT keyid, hash FROM api_key WHERE userid = ? AND state = 'A'},
            'keyid', undef, $user->{userid} );
        carp $dbr->errstr if $dbr->err;
        return undef unless $keys;
        my @hashlist;

        for my $key ( sort ( keys %$keys ) ) {
            my $new = $self->_create( $user, $keys->{$key}->{keyid}, $keys->{$key}->{hash} );
            push @hashlist, ( $keys->{$key}->{hash} );
            push @keylist,  ($new);
            my $cachekey = [ $new->{keyhash}, "api_key:" . $new->{keyhash} ];
            LJ::MemCache::set( $cachekey,
                { userid => $user->id, keyid => $new->{keyid}, hash => $new->{keyhash} } );
        }
        LJ::MemCache::set( $memkey, \@hashlist );
    }

    return \@keylist;
}

# Usage: create ( user, key )
# Creates and returns a new key object given a user and key hash.
# Don't call this directly, as it neither verifies nor saves keys.
# new() or lookup() is probably what you want instead.
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
    my $memkey = [ $self->{keyhash}, "api_key:" . $self->{keyhash} ];

    $self->valid_for_user($user) or croak "key doesn't belong to user";

    my $dbw = LJ::get_db_writer() or croak "Failed to get database";
    $dbw->do( q{UPDATE api_key SET state = 'D' WHERE state = 'A' AND hash = ?},
        undef, $self->{keyhash} );

    LJ::MemCache::delete($memkey);

    # with a new key added, our cached api_keys_list for the user is out of date
    LJ::MemCache::delete( [ $user->id, "api_keys_list:" . $user->id ] );

    return 1 unless $dbw->err;
    carp $dbw->errstr if $dbw->err;
    return undef;
}

sub valid_for_user {
    my ( $self, $u ) = @_;
    return $self->{user}->equals($u);
}

1;
