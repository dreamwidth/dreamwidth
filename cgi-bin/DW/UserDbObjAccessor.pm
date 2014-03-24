#!/usr/bin/perl
#
# DW::UserDbObjAccessor
#
# An accessor object for UserDbObjs.
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.


package DW::UserDbObjAccessor;
use strict;
use warnings;

# create a new instance
sub instance {
    my ( $class, $target_class, $u ) = @_;
    
    $u = LJ::want_user($u) or LJ::throw("no user");
    return bless {
        u => $u,
        target_class => $target_class,
        single_key_column => 'id',
    };
}
*new = \&instance;

sub target_class {
    return $_[0]->{target_class};
}

sub user {
    return $_[0]->{u};
}

sub single_key_column {
    return $_[0]->{single_key_column};
}

sub get_db_reader {
    my $u = $_[0]->user;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u);
    return $dbcm;
}
sub get_db_writer {
    my $u = $_[0]->user;
    my $dbcm = $u->{'_dbcm'} ||= LJ::get_cluster_master($u);
    return $dbcm;
}

# returns all of the objects for the requested user
sub _all_for_user {
    my ( $self ) = @_;

    my $all_for_user = $self->_all_items_by_value( "userid", $self->user->id );
    return $all_for_user;
}

# returns all matches for this use where the field-value pairs match
sub _fv_query_by_user {
    my ( $self, $field_value_map ) = @_;

    my %local_fv_map = %$field_value_map;
    $local_fv_map{userid} = $self->user->id;

    return $self->_all_items_by_values( \%local_fv_map );
}

# returns all of the objects for the requested value
# NOTE:  $field should _never_ be user provided, since we're
# putting it directly in the query.
sub _all_items_by_value {
    my ( $self, $field, $value ) = @_;
   
    return $self->_all_items_by_values( { $field => $value } );
}

# returns all of the objects for the requested value
# NOTE:  the keys in the field_value_map  should _never_ be user provided,
# since we're putting them directly in the query.
sub _all_items_by_values {
    my ( $self, $field_value_map ) = @_;
   
    my @ids = $self->_keys_by_values( $field_value_map );
    my $items = $self->_load_objs_from_keys( \@ids );

    return $items;
}

# returns all of the ids for the requested field/value pairs
# NOTE:  the keys in the field_value_map  should _never_ be user provided,
# since we're putting them directly in the query.
sub _keys_by_values {
    my ( $self, $field_value_map ) = @_;
    
    my $ids;
    my @objs;
    # see if we can get it from memcache
    if ( $self->target_class->memcache_query_enabled ) {
        $ids = $self->target_class->_load_keys( $field_value_map );
        if ( $ids && ref $ids eq 'ARRAY' && scalar @$ids > 1 ) {
            return wantarray ? @$ids : $ids;
        }
    }

    # if we didn't get anything from memcache, try the database

    # need a consistent order for fields to use for values
    my @fields =  sort keys %$field_value_map;
    my $where_clause = " " . join( ' AND ', map { "`$_`" . " = ?" } @fields ) . " ";
    my @values = map { $field_value_map->{$_} } @fields ;
    $ids = $self->_search_ids( $where_clause, \@values );
    
    if ( $self->target_class->memcache_query_enabled ) {
        $self->target_class->_store_keys( $field_value_map, $ids );
    }
    return wantarray ? @$ids : $ids;
}

# does the DB query for the appropriate values.
sub _search_ids {
    my ( $self, $where_clause, $values ) = @_;

    my $dbr = $self->get_db_reader();

    my $sql = "SELECT " . $self->single_key_column . " FROM " . $self->target_class->_tablename . " " .$self->target_class->_create_where_clause( $where_clause ) . " " . $self->target_class->_default_order_by;
    #warn("search_ids: running sql '$sql'");
    my $ids = $dbr->selectcol_arrayref( $sql, undef, @$values );
    LJ::throw( $dbr->errstr ) if $dbr->err;
    
    return $ids;
}

# retrieves a set of objects by ids for a user, either from database or 
# memcache as appropriate
sub _load_objs_from_keys {
    my ( $self, $keys ) = @_;

    # return an empty array for an empty request
    if ( ! defined $keys || ! scalar @$keys ) {
        return [];
    }

    # try from memcache first.  if we get all the results from memcache,
    # just return that.  otherwise, keep the misses and an id map for the
    # hits.
    my %memcache_objmap = ();
    my %db_objmap = ();
    my @memcache_misses = @$keys;
    if ( $self->target_class->memcache_enabled ) {
        my $cached_value = $self->_load_batch_from_memcache( $keys );
        @memcache_misses = @{$cached_value->{misses}};
        %memcache_objmap = %{$cached_value->{objmap}};
    }

    if ( @memcache_misses ) {
        # if we got to here, then we need to query the db for at least a 
        # subset of the objects
        my $dbr = $self->get_db_reader();

        my $qs = join( ', ', map { '?' } @memcache_misses );
        
        my $sql = "SELECT " . join ( ',' , ( 'userid', $self->single_key_column, $self->target_class->_obj_props ) ) . " FROM " . $self->target_class->_tablename . " WHERE userid = ? AND id IN ( $qs )";
        #warn ("running $sql");
        my $sth = $dbr->prepare( $sql );
        $sth->execute( $self->user->id, @memcache_misses );
        LJ::throw( $dbr->err ) if ( $dbr->err );
        
        # ok, now we create the objects from the db query
        my $obj;
        my @db_objs = ();
        while ( my $row = $sth->fetchrow_hashref ) {
            $obj = $self->target_class->_new_from_row( $self->user, $row );

            push @db_objs, $obj;
            $db_objmap{$obj->{$self->single_key_column}} = $obj;
        }

        # if we're using memcache, save the newly loaded objects to it.
        if ( $self->target_class->memcache_enabled ) {
            $self->target_class->_store_batch_to_memcache( \@db_objs );
        }
    }

    # stitch together the memcache results and the db results in the
    # original id order
    my @returnvalue = ();
    foreach my $key ( @$keys ) {
        if ( defined $db_objmap{$key} ) {
            push @returnvalue, $db_objmap{$key};
        } elsif ( defined $memcache_objmap{$key} ) {
            push @returnvalue,  $memcache_objmap{$key};
        }
    }
    
    return \@returnvalue;
}

# loads an entire batch of ids from memcache.
sub _load_batch_from_memcache {
    my $self = shift;
    my $ids = shift;
    my $u = $self->user;

    my @memcache_keys = ();
    my $keymap = {};
    for my $id ( @$ids ) {
        my $memcache_key = $self->target_class->_memcache_key( $u->id . ":" . $id );
        push @memcache_keys, $memcache_key->[1];
        $keymap->{$memcache_key->[1]} = $id;
    }
    my $mem = LJ::MemCache::get_multi( @memcache_keys );

    my ($version, @props) = $self->target_class->_memcache_stored_props;
    my @hits = ();
    my %misses = %$keymap;
    my @objects = ();
    my %objmap = ();
    while (my ($k, $v) = each %$mem) {
        if ( defined $v && ref $v eq 'ARRAY' ) {
            push @hits, $keymap->{$k};
            if ( $v->[0]==$version ) {
                my %hash;
                foreach my $i (0..$#props) {
                    $hash{ $props[$i] } = $v->[$i+1];
                }
                my $obj = $self->target_class->_memcache_hashref_to_object(\%hash);
                push @objects, $obj;
                $objmap{$keymap->{$k}}=$obj;
                delete $misses{$k};
            }
        }
    }
    my @misses = values %misses;
    return {
        hits => \@hits,
        misses => \@misses,
        objects => \@objects,
        objmap => \%objmap,
    };
}

# save an entire batch of ids to memcache.
sub _store_batch_to_memcache {
    my $self = shift;
    my $objs = shift;

    for my $obj ( @$objs ) {
        $obj->_store_to_memcache();
    }
}



1;

