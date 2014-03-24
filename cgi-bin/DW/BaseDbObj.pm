#!/usr/bin/perl
#
# Base class for DB objects
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
## _tablename { }
## _skeleton { } -- NOTE: the other methods here may be inherited, but 
##                  _skeleton() must be implemented by each subclass
##
## _memcache_id                 { $_[0]->userid                 }
## _memcache_key_prefix         { "user"                        }
## _memcache_stored_props       { qw/$VERSION name age caps /   }
## _memcache_hashref_to_object  { LJ::User->new_from_row($_[0]) }
## _memcache_expires            { 24*3600                       }

package DW::BaseDbObj;

use strict;
use warnings;

use base 'LJ::MemCacheable';

# Object key column.
sub _key_column {
    return "id";
}

# Editable properties for the object. Defaults to all; may be overridden.
sub _editable_obj_props {
    return $_[0]->_obj_props;
}

# returns the WHERE clause for searching by ID
sub _where_by_id {
    return "WHERE " . $_[0]->_key_column . " = ?";
}

# creates a WHERE clause for searching
sub _create_where_clause {
    my ( $class, $filter ) = @_;
    
    my $default_filter = $class->_default_filter;

    my $return_value = $filter || "";
    if ( ( $filter && $filter ne "" ) || ( $default_filter && $default_filter ne "" ) ) {
        if ( $default_filter && $default_filter ne "" ) {
            if ( $return_value && $return_value ne "" ) {
                $return_value .= " AND ";
            }
            $return_value .= $default_filter;
        }
        $return_value = " WHERE " . $return_value;
    }
    return $return_value;
}

sub _default_filter {
    return "";
}


# returns the full object key for this object
sub _key {
    my $self = $_[0];
    return $self->{$self->_key_column};
}

sub _default_order_by {
    return "";
}

# DB utils
sub get_db_writer {
    return LJ::get_db_writer();
}
sub get_db_reader {
    return LJ::get_db_reader();
}


# create a new instance
sub instance {
    my ( $class, $id ) = @_;
    
    my $obj = $class->_skeleton( $id );
    return $obj;
}
*new = \&instance;

# instance methods
sub _absorb_row {
    my ($self, $row) = @_;

    # set the key
    $self->{$self->_key_column} = $row->{$self->_key_column};
    # and set all the properties
    for my $f ( $self->_obj_props ) {
        $self->{$f} = $row->{$f};
    }
    return $self;
}

# creates an new DbObj from a DB row
sub _new_from_row {
    my ($class, $row) = @_;
    die unless $row && $row->{$class->_key_column};
    my $self = $class->new( $row->{$class->_key_column} );
    $self->_absorb_row($row);
    return $self;
}

# creates a new instance
sub _create {
    my ( $class, $opts ) = @_;

    # validate the inputs first
    $class->validate( $opts );

    my $dbh = $class->get_db_writer();
    # new objectid
    #my $objid = $class->_get_next_id();

    # create and run the SQL
    my $entrystring =  join ( ',' , $class->_obj_props );
    my $qs = join( ', ', map { '?' } $class->_obj_props );
    my @values = map { $opts->{$_} }  $class->_obj_props;
    my $sql = "INSERT INTO " . $class->_tablename . " ( $entrystring ) values ( $qs )";
    #warn("running $sql, values=" . join( ",", @values));
    $dbh->do( $sql, undef, @values );
    
    LJ::throw($dbh->errstr) if $dbh->err;

    my $objid = $dbh->selectrow_array( "SELECT LAST_INSERT_ID()" );

    # now return the created object.
    my $obj = $class->_get_obj( $objid ) or LJ::throw("Error instantiating object");

    # clear the appropriate caches for this object
    $obj->_clear_associated_caches();

    return $obj;
}

# updates an existing instance
sub _update {
    my ( $self ) = @_;

    # validate the inputs first
    $self->validate( $self );

    my $dbh = $self->get_db_writer();

    # create and run the SQL
    my $qs = join( ', ', map { $_ . "=?" } $self->_obj_props );
    my @values = map { $self->{$_} }  $self->_obj_props;
    my $sql = "UPDATE " . $self->_tablename . " set $qs WHERE " . $self->_key_column . "=?";
    #warn ("updating: running $sql ; values = " . join (',', @values ));
    $dbh->do( $sql, undef, @values, $self->id );
    
    LJ::throw($dbh->errstr) if $dbh->err;

    # return the updated object.
    my $obj = $self->by_id( $self->id ) or LJ::throw("Error instantiating object");

    # clear the cache.
    $obj->_clear_cache();
    $obj->_clear_associated_caches();

    return $obj;
}

# retrieves a single object by id, either from database or memcache
sub _get_obj {
    my ( $class, $objid ) = @_;

    my @keyarray = ( $objid );
    my @objarray = $class->_load_objs_from_keys( \@keyarray );
    if ( @objarray && scalar@objarray  ) {
        return $objarray[0];
    } else {
        return undef;
    }
}

# retrieves a set of objects by ids, either from database or memcache
# as appropriate
sub _load_objs_from_keys {
    my ( $class, $keys ) = @_;

    # return an empty array for an empty request
    if ( ! defined $keys || ! scalar @$keys ) {
        return ();
    }
    #warn("loading objs from keys ( " . join(",", @$keys ) . " ) ");

    # try from memcache first.  if we get all the results from memcache,
    # just return those.  otherwise, keep the misses and an id map for the
    # hits.
    my %memcache_objmap = ();
    my %db_objmap = ();
    my @memcache_misses = @$keys;
    if ( $class->memcache_enabled ) {
        my $cached_value = $class->_load_batch_from_memcache( $keys );
        @memcache_misses = @{$cached_value->{misses}};
        %memcache_objmap = %{$cached_value->{objmap}};
    }

    if ( @memcache_misses ) {
        # if we got to here, then we need to query the db for at least a 
        # subset of the objects
        my $dbr = $class->get_db_reader();

        my $qs = join( ', ', map { '?' } @memcache_misses );
        my $sql = "SELECT " . join ( ',' , ( $class->_key_column, $class->_obj_props ) ) . " FROM " . $class->_tablename . " WHERE ".  $class->_key_column . " IN ( $qs )";
        #warn("running $sql, values = " . join (',', @memcache_misses ));
        my $sth = $dbr->prepare( $sql );
        $sth->execute( @memcache_misses );
        LJ::throw( $dbr->err ) if ( $dbr->err );
        
        # ok, now we create the objects from the db query
        my $obj;
        my @db_objs = ();
        while ( my $row = $sth->fetchrow_hashref ) {
            $obj = $class->_new_from_row( $row );
            push @db_objs, $obj;
            $db_objmap{$obj->_key} = $obj;
        }

        # if we're using memcache, save the newly loaded objects to it.
        if ( $class->memcache_enabled ) {
            $class->_store_batch_to_memcache( \@db_objs );
        }
    }

    # stitch together the memcache results and the db results in the
    # original id order
    my @returnvalue = ();
    foreach my $key ( @$keys ) {
        push @returnvalue, $db_objmap{$key} || $memcache_objmap{$key};
    }
    return @returnvalue;
}

# updates this object's values from the provided object (or hash)
sub _copy_from_object {
    my ( $self, $source ) = @_;

    # go through each property available and, if it's set, copy it to
    # this object.
    foreach my $prop ( $self->_editable_obj_props ) {
        if ( exists $source->{$prop} ) {
            $self->{$prop} = $source->{$prop};
        }
    }
}

# updates this object's values from the provided object (or hash).
sub copy_from_object {
    my ( $self, @args ) = @_;
    $self->_copy_from_object( @args );
}

# deletes this object.  may be overridden by subclasses.
sub delete {
    return $_[0]->_delete();
}

# deletes this object
sub _delete {
    my ( $self ) = @_;
    
    my $dbh = $self->get_db_writer();
    #warn("deleting " . $self->_key);
    $dbh->do("DELETE FROM " . $self->_tablename . " " . $self->_where_by_id, 
           undef, $self->_key );

    # clear the cache.
    $self->_clear_cache();
    $self->_clear_associated_caches();

    return 1;
}


# clears the cache for the given item
sub _clear_cache {
    my ( $self ) = @_;

    $self->_remove_obj_from_memcache( $self );
}

# clears the cache for the given item
sub _clear_associated_caches {
    my ( $self ) = @_;
    
    #my $data = $class->_load_from_memcache( "q:$field:$value" );
    #LJ::MemCache::delete( $class->_memcache_key( "q:userid:" . $self->{userid} ) );
    # a no-op by default; subclasses should override
}

# does the DB query for the appropriate values. 
sub _search_ids {
    my ( $class, $where_clause, @values ) = @_;

    my $dbr = $class->get_db_reader();

    my $sql = "SELECT " . $class->_key_column . " FROM " . $class->_tablename . " " . $class->_create_where_clause( $where_clause ) . " " . $class->_default_order_by;
    #warn("running $sql, values - " . join (",", @values ) );
    my $ids = $dbr->selectcol_arrayref( $sql, undef, @values );
    LJ::throw( $dbr->errstr ) if $dbr->err;
    
    #warn("for search_ids, got $ids - scalar " . scalar @$ids . "; values " . join(",", @$ids ) );
    return $ids;
}

# returns all of the objects for the requested value
# NOTE:  $field should _never_ be user provided, since we're
# putting it directly in the query.
sub _all_items_by_value {
    my ( $class, $field, $value ) = @_;
   
    my @ids = $class->_keys_by_value( $field, $value );
    my @items = $class->_load_objs_from_keys( \@ids );

    return @items;
}

# returns all of the ids for the requested value
# NOTE:  $field should _never_ be user provided, since we're
# putting it directly in the query.
sub _keys_by_value {
    my ( $class, $field, $value ) = @_;

    my $ids;
    my @objs;
    # see if we can get it from memcache
    if ( $class->memcache_query_enabled ) {
        $ids = $class->_load_keys( { $field => $value } );
        if ( $ids && ref $ids eq 'ARRAY' && scalar @$ids > 1 ) {
            return wantarray ? @$ids : $ids;
        }
    }

    # if we didn't get anything from memcache, try the database
    my $where_clause =  " $field = ?";
    $ids = $class->_search_ids( $where_clause, $value );

    if ( $class->memcache_query_enabled ) {
        $class->_store_keys( { $field => $value }, $ids );
    }
    return wantarray ? @$ids : $ids;
}

# returns all of the ids that match the given search
sub _keys_by_search {
    my ( $class, $search ) = @_;

    #warn("running _keys_by_search");
    my $ids;
    # see if we can get it from memcache
    my @objs;
    # see if we can get it from memcache
    # FIXME figure out how to make a proper key for search, as well as
    # how to clear those (dynammic) searches on update
    #if ( $class->memcache_query_enabled ) {
        #warn("running _keys_by_value for memcache.");
        #$ids = $class->_load_keys( { $field => $value } );
        #warn("got $ids");
        #if ( $ids && ref $ids eq 'ARRAY' && scalar @$ids > 1 ) {
            #warn("(not) returning ids - " . join(",", @$ids ) );
        #    return wantarray ? @$ids : $;
        #}
    #}
    
    # if we didn't get anything from memcache, try the database
    
    #warn("checking db");
    my $where_clause = "";
    my @values = ();
    foreach my $searchterm ( @$search ) {
        #warn("adding searchterm");
        if ( $searchterm->{conjunction} ) {
            $where_clause .= $searchterm->{conjunction} . " ";
        }
        $where_clause .= $searchterm->{whereclause} . " ";
        if ( $searchterm->{values} ) {
            push @values, @$searchterm->{values};
        } elsif ( $searchterm->{value} ) {
            push @values, $searchterm->{value};
        }
        #warn("whereclause = " . $where_clause);
    }
    $ids = $class->_search_ids( $where_clause, @values );
    #warn("searched ids; got $ids - " . join(",", @$ids ));
    
    #if ( $class->memcache_query_enabled ) {
    #    $class->_store_keys( { $field => $value }, $ids );
    #}
    return wantarray ? @$ids : $ids;
}

# creates a search hash for a given key and value set. this version just
# does simple column comparisons; subclasses sould provide more complex
# examples
sub create_searchterm {
    my ( $class, $key, $comparator, @values ) = @_;
    # only allow registered columns
    if ( grep {$_ eq $key} $class->_obj_props ) {
        my $whereclause = " $key $comparator ";
        #warn ("using values @values");
        if ( scalar @values > 1 ) {
            $whereclause .= "(" . join( ', ', map { '?' } @values ) . ") ";
        } else {
            $whereclause .= "? ";
        }
        my $term = {
            column => $key,
            comparator => $comparator,
            whereclause => $whereclause,
        };
        if ( scalar @values > 1 ) {
            $term->{values} = \@values,
        } else {
            $term->{value} = $values[0];
        }
        return $term;
    }

    return 0;
}


# creates the appropriate key for the given set of key/value pairs
sub _create_memc_fvmap_key {
    my ( $class, $field_value_map ) = @_;

    my $returnvalue = 'q:' . join( ':', map { "$_" . ":" . $field_value_map->{$_} } sort keys %$field_value_map );
}

# loads a list of keys from memcache
sub _load_keys {
    my ( $class, $field_value_map ) = @_;

    my $id = $class->_create_memc_fvmap_key( $field_value_map );
    my $memc_key = $class->_memcache_key( $id );
    my $data = LJ::MemCache::get( $memc_key );
    return unless $data && ref $data eq 'ARRAY';

    return $data;
}

# saves a list of keys to memcache
sub _store_keys {
    my ( $class, $field_value_map, $keys ) = @_;

    my $id = $class->_create_memc_fvmap_key( $field_value_map );
    my $memc_key = $class->_memcache_key( $id );
    LJ::MemCache::set( $memc_key, $keys, $class->_memcache_expires);
}

# saves a list of keys to memcache
sub _clear_keys {
    my ( $class, $field_value_map ) = @_;

    my $id = $class->_create_memc_fvmap_key( $field_value_map );
    my $memc_key = $class->_memcache_key( $id );
    LJ::MemCache::delete( $memc_key );
}


# returns the next available id
sub _get_next_id {
    my ( $class, $dbh ) = @_;
    
    return LJ::alloc_global_counter( $class->_globalcounter_id );
}

#validates the new object.  should be overridden by subclasses
sub validate {
    my ( $class, $opts ) = @_;

    return 1;
}

# returns the id of this object.
sub id {
    return $_[0]->{_obj_id};
}

# returns the object with the given id
sub by_id {
    my ( $class, $id ) = @_;

    return $class->_get_obj( $id );
}

#updates
sub update {
    my ( $self ) = @_;

    $self->_update();
}

# default memcache implementations

# use memcache for object storage
sub memcache_enabled { 1 }
# use memcache for search queries
sub memcache_query_enabled { 0 }

sub _memcache_id {
    return $_[0]->id;
}

# returns the properties stored in memcache for this object.
# default implementation:  returns the keys and properties of the object
sub _memcache_stored_props {
    my $class = $_[0];

    # first element of props is a VERSION
    # next - allowed object properties
    return (  $class->_memcache_version, $class->_key_column, $class->_obj_props );
}

# create a new object from a memcache row
sub _memcache_hashref_to_object {
    my ($class, $row) = @_;
    return $class->_new_from_row( $row );
}

# default expiration
sub _memcache_expires  { 24*3600 }

# loads an entire batch of ids from memcache.
sub _load_batch_from_memcache {
    my $class = shift;
    my $ids = shift;

    my @memcache_keys = ();
    my $keymap = {};
    # get the memcache keys for each of the provided object ids
    for my $id ( @$ids ) {
        my $memcache_key = $class->_memcache_key( $id );
        push @memcache_keys, $memcache_key->[1];
        $keymap->{$memcache_key->[1]} = $id;
    }
    my $mem = LJ::MemCache::get_multi( @memcache_keys );

    my ($version, @props) = $class->_memcache_stored_props;
    my @hits = ();
    my %misses = %$keymap;
    my @objects = ();
    my %objmap = ();
    # go through each returned value, map it by id, and then remove it from
    # the misses list
    while (my ($k, $v) = each %$mem) {
        if ( defined $v && ref $v eq 'ARRAY' ) {
            push @hits, $keymap->{$k};
            if ( $v->[0] == $version ) {
                my %hash;
                foreach my $i (0..$#props) {
                    $hash{ $props[$i] } = $v->[$i+1];
                }
                my $obj = $class->_memcache_hashref_to_object(\%hash);
                push @objects, $obj;
                $objmap{$keymap->{$k}}=$obj;
                delete $misses{$k};
            }
        }
    }
    my @misses = values %misses;
    #warn("returning; hits=@hits, misses=@misses objects=@objects, objmap=" . %objmap );
    return {
        hits => \@hits,
        misses => \@misses,
        objects => \@objects,
        objmap => \%objmap,
    };
}

# save an entire batch of ids to memcache.
sub _store_batch_to_memcache {
    my $class = shift;
    my $objs = shift;

    # from what i can tell this is as efficient as trying to do it in batch
    for my $obj ( @$objs ) {
        $obj->_store_to_memcache();
    }
}

## warning: instance or class method.
## $id may be absent when calling on instance.
sub _remove_obj_from_memcache {
    my $class = shift;
    my $object = shift;

    LJ::MemCache::delete($object->_memcache_key );
}

1;

