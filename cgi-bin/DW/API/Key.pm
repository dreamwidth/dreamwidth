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
    my $user = $_[0];
    die "Invalid user object" unless $LJ::isu( $user );

    # TODO: update code in cgi-bin/LJ/DB.pm to add a new counter and tables
    my $id = LJ::alloc_user_counter( $user, 'B' )
        or croak 'Unable to allocate user counter for API key.';

    # TODO: is this sufficient randomness?
    my $key = LJ::rand_chars( 32 );
    $user->do(
        q{INSERT INTO api_key (userid, keyid, hash, state)
         VALUES (?, ?, ?, 'A')},
        undef, $user->id, $id, $key
    );
    croak "Failed to insert key row: " . $user->errstr . "."
        if $user->err;

    return _create($user, $id, $key);
}

# Usage: lookup ( user, key ) 
# Looks for a given key for a user. Returns the key object
# if it's valid, or undef otherwise.
sub lookup {
    my ($user, $hash) = @_;
    die "Invalid user object" unless $LJ::isu( $user );

    my $key = $user->selectrow_hashref(
            q{SELECT keyid, hash FROM apikey WHERE userid = ? AND hash = ? AND state = 'A'},
            'keyid', undef, $user->{userid}, $hash
        );
    confess $user->errstr if $user->err;

    return undef unless $key;
    return _create($user, $key->{keyid}, $key);
}

# Usage: lookup_all ( user ) 
# Looks up all API keys for a given user. Returns an arrayef of key objects,
# or undef if the user has no API keys yet.
sub lookup_all {
    my $user = $_[0];
    die "Invalid user object" unless $LJ::isu( $user );

    my $keys = $user->selectall_hashref(
            q{SELECT keyid, hash FROM apikey WHERE userid = ? AND state = 'A'},
            'keyid', undef, $user->{userid}
        );
    confess $user->errstr if $user->err;

    return undef unless $keys;
    my @keylist;

    for my $key (sort (keys %$keys)) {
        my $new = _create($user, $keys->{$key}->{keyid}, $keys->{$key}->{hasg});
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
        keyid => $id,
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
    return true;
}

# Usage: $key->can_write( resource ) 
# Checks if a key has been given write permissions
# for a given resource by the user it belongs to.

sub can_write {
    my ($self, $resource) = @_;

    #TODO: Once key scoping is implemented, actually check this
    return true;
}

*LJ::User::generate_apikey = \&new;
*LJ::User::get_all_keys = \&lookup_all;