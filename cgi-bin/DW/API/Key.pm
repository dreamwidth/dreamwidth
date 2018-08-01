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
    my ($self, $u) = @_;
    my $user = LJ::want_user( $u )
        or die "need a user!\n";

    my $id = LJ::alloc_user_counter( $user, 'B' )
        or croak 'Unable to allocate user counter for API key.';

    my $key = LJ::rand_chars( 32 );
    my $dbw = LJ::get_db_writer() or die "Failed to get database";
    $dbw->do(
        q{INSERT INTO api_key (userid, keyid, hash, state)
         VALUES (?, ?, ?, 'A')},
        undef, $user->id, $id, $key
    );

    if ($dbw->err) {
       carp "Failed to insert key row: " . $dbw->errstr . ".";
        return undef;
    }

    return $self->_create($user, $id, $key);
}

# Usage: lookup ( user, key ) 
# Looks for a given key for a user. Returns the key object
# if it's valid, or undef otherwise.
sub get_key {
    my ($class, $hash) = @_;

    return undef unless $hash;
    # my $memkey = [ $userid, "user_oauth_access:" . $userid ];
    my $data = undef; # LJ::MemCache::get( $memkey );
    my $key;

    if ( $data ) {
        $key = $data;
        return $key;
    } else {
        my $dbr = LJ::get_db_reader() or die "Failed to get database";
        my $keydata = $dbr->selectrow_hashref( "SELECT keyid, userid, hash FROM api_key WHERE hash = ? AND state = 'A'", undef, $hash );
        carp $dbr->errstr if $dbr->err;

        if ($keydata) {
            my $user = LJ::want_user( $keydata->{userid} );
            $key = $class->_create($user, $keydata->{keyid}, $keydata->{hash});
            #LJ::MemCache::set( $memkey, $key );
            return $key
        }

    }

    return undef;
}

# Usage: get_keys_for_user ( user ) 
# Looks up all API keys for a given user. Returns an arrayef of key objects,
# or undef if the user has no API keys yet.
sub get_keys_for_user {
    my ($self, $u) = @_;
    my $user = LJ::want_user( $u )
        or die "need a user!\n";

    my $dbr = LJ::get_db_reader() or die "Failed to get database";
    my $keys = $dbr->selectall_hashref( 
            q{SELECT keyid, hash FROM api_key WHERE userid = ? AND state = 'A'},
            'keyid', undef, $user->{userid} 
        );
    carp $dbr->errstr if $dbr->err;

    return undef unless $keys;
    my @keylist;

    for my $key (sort (keys %$keys)) {
        my $new = $self->_create($user, $keys->{$key}->{keyid}, $keys->{$key}->{hash});
        push @keylist, ($new);
    }

    return \@keylist;
}



# Usage: create ( user, key ) 
# Creates and returns a new key object given a user and key hash.
# Don't call this directly, as it neither verifies nor saves keys.
# new() or lookup() is probably what you want instead. 
sub _create {
    my ($class, $user, $keyid, $keyhash) = @_;

    my %key = (
        user => $user,
        keyid => $keyid,
        keyhash => $keyhash
        );

    bless \%key, $class;
    return \%key;
}

# Usage: $key->can_read( resource ) 
# Checks if a key has been given read permissions
# for a given resource by the user it belongs to.

sub can_read {
    my ($self, $resource) = @_;

    #TODO: Once key scoping is implemented, actually check this
    return 1;
}

# Usage: $key->can_write( resource ) 
# Checks if a key has been given write permissions
# for a given resource by the user it belongs to.

sub can_write {
    my ($self, $resource) = @_;

    #TODO: Once key scoping is implemented, actually check this
    return 1;
}

# Usage: $key->delete () 
# Marks a key as deleted in the DB
sub delete {
    my $self = $_[0];
    my $user = LJ::want_user( $self-> {user} )
        or die "need a user!\n";

    my $dbw = LJ::get_db_writer() or die "Failed to get database";
    $dbw->do(
        q{UPDATE api_key SET state = 'D' WHERE hash = ?},
        undef, $self->{keyhash}
    );

    return 1 unless $dbw->err;
    carp $dbw->errstr if $dbw->err;
    return undef;
}

sub valid_for_user{
    my ($self, $u) = @_;
    return $self->{user}->equals($u);
}

1;