#!/usr/bin/perl
#
# DW::UserDbObj
#
# Base class for DB objects that belong to a user
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.



## Derived classes must implement the following methods:
## 
## _obj_props { }
## _usercounter_id { } ## see LJ::alloc_user_counter in LJ/DB.pm
## _skeleton { }
## _tablename { }
##
## _memcache_id                 { $_[0]->userid                 }
## _memcache_key_prefix         { "myobjname"                        }
## _memcache_stored_props       { qw/$VERSION name age caps /   }
## _memcache_hashref_to_object  { LJ::User->new_from_row($_[0]) }
## _memcache_expires            { 24*3600                       }

package DW::UserDbObj;
use strict;
use warnings;
use DW::UserDbObjAccessor;
#use Carp qw(cluck);

use base 'DW::BaseDbObj';

# returns the WHERE clause for searching by ID
sub _where_by_id {
    return "WHERE " . join ( ' AND ', map { $_ . "=?" } $_[0]->_key_column );
}

# returns the full object key(userid and objectid) for this object
sub _key {
    return map { $_[0]->{$_} }  $_[0]->_key_column;
}

# returns the full object key(userid and objectid) for this object
sub _key_column {
    return qw ( userid id );
}

# default memcache implementations
sub _memcache_id {
    return $_[0]->{_userid} . ":" . $_[0]->{_obj_id};
}
sub _memcache_stored_props          {
    my $class = $_[0];

    # first element of props is a VERSION
    # next - allowed object properties
    return ( $class->_memcache_version, $class->_key_column, $class->_obj_props );
}
sub _memcache_hashref_to_object {
    my ($class, $row) = @_;
    my $u = LJ::load_userid($row->{userid});
    return $class->_new_from_row($u, $row);
}

sub _memcache_expires  { 24*3600 }

#sub _memcache_key_prefix            { "keyprefix" }

# note: remember to change the _memcache_version every time the _key_column or
# _obj_props changes.
#sub _memcache_version { "1" }

# creates a new instance of a UserDbObj.
sub instance {
    my ( $class, $u, $id ) = @_;

    my $obj = $class->_skeleton( $u, $id );
    return $obj;
}
*new = \&instance;

# creates an new UserDbObj from a DB row.  Overrides BaseDbObj _new_from_row.
sub _new_from_row {
    my ($class, $u, $row) = @_;
    die unless $row && $row->{userid} && $row->{id};
    my $self = $class->new($u, $row->{id});
    $self->_absorb_row($row);
    return $self;
}

# creates a new instance
sub create {
    my ( $class, $u, $opts ) = @_;
    $class->_create( $u, $opts );
}

# creates a new instance
sub _create {
    my ( $class, $u, $opts ) = @_;

    # validate the inputs first
    $class->validate( $u, $opts );

    # new objectid
    my $objid = LJ::alloc_user_counter($u, $class->_usercounter_id );

    # create and run the SQL
    my $entrystring =  join ( ',' , $class->_obj_props );
    my $qs = join( ', ', map { '?' } $class->_obj_props );
    my @values = map { $opts->{$_} }  $class->_obj_props;

    my $sql = "INSERT INTO " . $class->_tablename . " ( " . join(",", $class->_key_column) . ",$entrystring ) values ( ?, ?, $qs )";
    #warn("running '$sql', values " . $u->{userid} . ", " .  $objid . ", " . join(", ", @values ) );
    $u->do( $sql, undef, $u->{userid}, $objid, @values );
    LJ::throw($u->errstr) if $u->err;

    # now return the created object.
    my $obj = $class->_get_obj( $u, $objid ) or LJ::throw("Error instantiating object");

    # clear the cache.
    $obj->_clear_associated_caches();

    return $obj;
}

# updates an existing instance
sub update {
    my ( $self ) = @_;

    my $u = $self->user;

    # validate the inputs first
    $self->validate( $self->user, $self );

    # create and run the SQL
    my $qs = join( ', ', map { $_ . "=?" } $self->_obj_props );
    my $key_query = join( ', ', map { $_ . "=?" } $self->_key_column );
    my @values = map { $self->{$_} }  $self->_obj_props;
    $u->do( "UPDATE " . $self->_tablename . " set $qs ". $self->_where_by_id , undef, @values, $self->_key );
    
    LJ::throw($u->errstr) if $u->err;

    # now return the created object.
    my $obj = $self->_get_obj( $u, $self->{_obj_id} ) or LJ::throw("Error instantiating object");

    # clear the cache.
    $self->_clear_cache();
    $self->_clear_associated_caches();

    return $obj;
}

# retrieves a single object by id, either from database or memcache
sub _get_obj {
    my ( $class, $u, $objid ) = @_;

    # try from memcache first.
    my $cached_value = $class->_load_from_memcache( $u->userid . ":$objid" );
    if ($cached_value) {
        return $cached_value;
    }

    # if that didn't work, run the select
    my $sth = $u->prepare( "SELECT " . join ( ',' , ( $class->_key_column, $class->_obj_props ) ) . " FROM " . $class->_tablename . " " .$class->_where_by_id );
    $sth->execute( $u->userid, $objid );
    LJ::throw( $u->err ) if ( $u->err );

    my $obj;
    if ( my $row = $sth->fetchrow_hashref ) {
        $obj = $class->_new_from_row($u, $row);
    }
    $obj->_store_to_memcache if $obj;

    return $obj;
}

# returns all of the objects for the requested user
sub all_for_user {
    my ( $class, $u ) = @_;
    
    # we require a user here.
    $u = LJ::want_user($u) or LJ::throw("no user");

    return DW::UserDbObjAccessor->new( $class, $u )->_all_for_user();
}


# deletes this object
sub delete {
    my ($self) = @_;
    my $u = $self->user;

    $u->do("DELETE FROM " . $self->_tablename . " " . $self->_where_by_id, 
           undef, $self->_key );

    # clear the cache.
    $self->_clear_cache();
    $self->_clear_associated_caches();

    return 1;
}

# clears associated cache for add/delete
sub _clear_associated_caches() {
    my ($self) = @_;

    #cluck("MMM clearing associated cache for " . $self . ", userid=" .  $self->user->id);
    $self->_clear_keys( { "userid" => $self->user->id } );
}

# available for all UserDbObjs
sub user {
    my $self = $_[0];

    if ( ! $self->{user} ) {
        my $user = LJ::load_userid( $self->{_userid} );
        $self->{user} = $user;
    }
    return $self->{user};
}

# validates the new object.  should be overridden by subclasses
sub validate {
    my ( $class, $u, $opts ) = @_;
    
    # we require a user here.

    $u = LJ::want_user($u) or LJ::throw("no user");

    return 1;
}

# gets a UserDbObj by id and user. may be overridden by subclasses if they
# require more than the default functionality
sub by_id {
    my ( $class, $u, $id ) = @_;

    return $class->_get_obj( $u, $id );
}

1;
