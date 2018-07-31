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

# Usage: new ( user ) 
# Creates a new API key for a given user, saves it to DB, 
# and returns the new key object.
sub new {
    my $user = LJ::want_user( $_[0] )
        or die "need a user!\n";

    my $id = LJ::alloc_user_counter( $user, 'B' )
        or croak 'Unable to allocate user counter for API key.';

    my $key = LJ::rand_chars( 32 );
    $user->do(
        q{INSERT INTO api_key (userid, keyid, hash, state)
         VALUES (?, ?, ?, 'A')},
        undef, $user->id, $id, $key
    );

    if ($user->err) {
       carp "Failed to insert key row: " . $user->errstr . ".";
        return undef;
    }

    return _create($user, $id, $key);
}

# Usage: lookup ( user, key ) 
# Looks for a given key for a user. Returns the key object
# if it's valid, or undef otherwise.
sub lookup {
    my ($u, $hash) = @_;
    my $user = LJ::want_user( $u )
        or die "need a user!\n";

    my $key = $user->selectrow_hashref(
            q{SELECT keyid, hash FROM api_key WHERE userid = ? AND hash = ? AND state = 'A'},
            undef, $user->{userid}, $hash
        );
    carp $user->errstr if $user->err;

    return undef unless $key;
    return _create($user, $key->{keyid}, $key->{hash});
}

# Usage: lookup_all ( user ) 
# Looks up all API keys for a given user. Returns an arrayef of key objects,
# or undef if the user has no API keys yet.
sub lookup_all {
    my $user = LJ::want_user( $_[0] )
        or die "need a user!\n";

    my $keys = $user->selectall_hashref(
            q{SELECT keyid, hash FROM api_key WHERE userid = ? AND state = 'A'},
            'keyid', undef, $user->{userid}
        );
    carp $user->errstr if $user->err;

    return undef unless $keys;
    my @keylist;

    for my $key (sort (keys %$keys)) {
        my $new = _create($user, $keys->{$key}->{keyid}, $keys->{$key}->{hash});
        push @keylist, ($new);
    }

    return \@keylist;
}



# Usage: create ( user, key ) 
# Creates and returns a new key object given a user and key hash.
# Don't call this directly, as it neither verifies nor saves keys.
# new() or lookup() is probably what you want instead. 
sub _create {
    my ($user, $keyid, $keyhash) = @_;

    my %key = (
        user => $user,
        keyid => $keyid,
        keyhash => $keyhash
        );

    bless \%key;
    return \%key;
}

# Usage: $key->can_read( resource ) 
# Checks if a key has been given read permissions
# for a given resource by the user it belongs to.

sub can_read {
    my ($self, $resource) = @_;

    #TODO: Once key scoping is implemented, actually check this
    return "true";
}

# Usage: $key->can_write( resource ) 
# Checks if a key has been given write permissions
# for a given resource by the user it belongs to.

sub can_write {
    my ($self, $resource) = @_;

    #TODO: Once key scoping is implemented, actually check this
    return "true";
}

# Usage: delete ( user, key ) 
# Marks a key as deleted in the DB
sub delete {
    my $self = $_[0];
    my $user = LJ::want_user( $self-> {user} )
        or die "need a user!\n";

    $user->do(
        q{UPDATE api_key SET state = 'D' WHERE hash = ?},
        undef, $self->{keyhash}
    );

    return 'true' unless $user->err;
    carp $user->errstr if $user->err;
    return undef;
}

*LJ::User::generate_apikey = \&new;
*LJ::User::get_all_keys = \&lookup_all;
*LJ::User::get_key = \&lookup;
