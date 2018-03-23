#!/usr/bin/perl
#
# DW::BlobStore
#
# Meta storage API for storing arbitrary blobs of content by key.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2016-2018 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::BlobStore;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger( __PACKAGE__ );

use File::Temp;

use DW::Stats;
use LJ::ModuleLoader;

LJ::ModuleLoader->require_subclasses('DW::BlobStore');

my $blobstores;

sub _get_blobstores {
    # If we've already created one, simply return it.
    return $blobstores if defined $blobstores;

    # If we're in the middle of a test, create a new temporary directory and set
    # up localdisk only.
    if ( LJ::in_test() ) {
        my $dir = File::Temp::tempdir( CLEANUP => 1 );
        $blobstores = [
            DW::BlobStore::LocalDisk->init( path => $dir )
        ];
        return $blobstores;
    }

    my $idx = 0;
    while ( $idx < scalar @LJ::BLOBSTORES ) {
        my ( $name, $config ) = @LJ::BLOBSTORES[$idx, $idx+1];
        $log->logcroak( 'Value must be a hashref.' )
            unless $config && ref $config eq 'HASH';

        if ( $name eq 'localdisk' ) {
            push @{$blobstores ||= []}, DW::BlobStore::LocalDisk->init( %$config );
        } elsif ( $name eq 'mogilefs' ) {
            push @{$blobstores ||= []}, DW::BlobStore::MogileFS->init( %$config );
        } elsif ( $name eq 's3' ) {
            push @{$blobstores ||= []}, DW::BlobStore::S3->init( %$config );
        } else {
            $log->logcroak( 'Invalid blobstore type: ' . $name );
        }

        $idx += 2;
    }

    $log->logcroak( 'Must configure @LJ::BLOBSTORES.' )
        unless $blobstores;
    $log->debug( 'Blobstore initialized with ', scalar( @$blobstores ), ' blobstores.' );
    return $blobstores;
}

# Check validity of namespace. Dies if invalid.
sub ensure_namespace_is_valid {
    my ( $namespace ) = @_;

    # Ensure that namespace is alpha-numeric
    unless ( $namespace =~ m!^(?:[a-z][a-z0-9]+)$! ) {
        DW::Stats::increment( 'dw.blobstore.error.namespace_invalid', 1 );
        $log->logcroak( "Namespace '$namespace' is invalid." );
    }
    return 1;
}

# Check validity of key. Dies if key is invalid.
sub ensure_key_is_valid {
    my ( $key ) = @_;

    # This is just a check to ensure that nobody uses a key without path
    # elements or with invalid characters.
    unless ( $key =~ m!^(?:[a-z0-9]+[_:/-])+([a-z0-9]+)$! ) {
        DW::Stats::increment( 'dw.blobstore.error.key_invalid', 1 );
        $log->logcroak( "Key '$key' is invalid." );
    }
    return 1;
}

# Store a file. File must be a scalarref. Return value is 1 if it was stored somewhere,
# and 0 if not. File will be stored to only one store.
sub store {
    my ( $class, $namespace, $key, $blobref ) = @_;
    ensure_namespace_is_valid( $namespace );
    ensure_key_is_valid( $key );
    $log->logcroak( 'Store requires data be a scalar reference.' )
        unless ref $blobref eq 'SCALAR';
    $log->debug( "Meta-blobstore: storing ($namespace, $key)" );

    # Enforce read-only mode
    if ( $LJ::DISABLE_MEDIA_UPLOADS ) {
        $log->info( 'Denying write due to $LJ::DISABLE_MEDIA_UPLOADS being set.' );
        return 0;
    }

    # Storage requests always go to the first blobstore that will take them,
    # we never store something twice.
    foreach my $bs ( @{$class->_get_blobstores} ) {
        my $rv = $bs->store( $namespace, $key, $blobref );
        if ( $rv ) {
            DW::Stats::increment( 'dw.blobstore.action.store_ok', 1, [ 'store:' . $bs->type ] );
            return $rv;
        } else {
            DW::Stats::increment( 'dw.blobstore.action.store_failed', 1, [ 'store:' . $bs->type ] );
        }
    }
    $log->info( "Meta-blobstore: failed to store ($namespace, $key)" );
    DW::Stats::increment( 'dw.blobstore.action.store_error', 1 );
    return 0;
}

# Delete a file from ALL known stores. Return 1 if it was deleted at least once,
# else return 0.
sub delete {
    my ( $class, $namespace, $key ) = @_;
    ensure_namespace_is_valid( $namespace );
    ensure_key_is_valid( $key );
    $log->debug( "Meta-blobstore: deleting ($namespace, $key)" );

    # Enforce read-only mode
    if ( $LJ::DISABLE_MEDIA_UPLOADS ) {
        $log->info( 'Denying write due to $LJ::DISABLE_MEDIA_UPLOADS being set.' );
        return 0;
    }

    # Deletes must be sent to all blobstores. Return true if any accepted
    # the delete.
    my $rv = 0;
    foreach my $bs ( @{$class->_get_blobstores} ) {
        $rv = $bs->delete( $namespace, $key ) || $rv;
    }
    if ( $rv ) {
        DW::Stats::increment( 'dw.blobstore.action.delete_ok', 1 );
    } else {
        # No 'failed' stat, delete operations can only fail entirely and not per-store since
        # we are for sure sending deletes to all stores
        DW::Stats::increment( 'dw.blobstore.action.delete_error', 1 );
    }
    return $rv;
}

# Retrieves a file from the blobstore. May return either a scalar-ref if the file
# was found, or returns undef.
sub retrieve {
    my ( $class, $namespace, $key ) = @_;
    ensure_namespace_is_valid( $namespace );
    ensure_key_is_valid( $key );
    $log->debug( "Meta-blobstore: retrieving ($namespace, $key)" );

    # Try blobstores in priority order.
    my $num_failures = 0;
    foreach my $bs ( @{$class->_get_blobstores} ) {
        my $rv = $bs->retrieve( $namespace, $key );
        if ( $rv ) {
            if ( $num_failures == 1 ) {
                # If we're in a migration, we often expect to see one failure followed by a
                # success. In that case, we want to cascade a store off of this retrieve to
                # store the file.
                $log->info( "Meta-blobstore: cascading store for ($namespace, $key)" );
                if ( $class->store( $namespace => $key, $rv ) ) {
                    DW::Stats::increment( 'dw.blobstore.action.retrieve_cascade_ok', 1 );
                } else {
                    DW::Stats::increment( 'dw.blobstore.action.retrieve_cascade_error', 1 );
                }
            }
            DW::Stats::increment( 'dw.blobstore.action.retrieve_ok', 1, [ 'store:' . $bs->type ] );
            return $rv;
        } else {
            $num_failures++;
            DW::Stats::increment( 'dw.blobstore.action.retrieve_failed', 1, [ 'store:' . $bs->type ] );
        }
    }
    $log->info( "Meta-blobstore: failed to retrieve ($namespace, $key)" );
    DW::Stats::increment( 'dw.blobstore.action.retrieve_error', 1 );
    return undef;
}

# Check if a file exists in any defined store. Returns 1 if it does, 0 if not.
sub exists {
    my ( $class, $namespace, $key ) = @_;
    ensure_namespace_is_valid( $namespace );
    ensure_key_is_valid( $key );
    $log->debug( "Meta-blobstore: checking if exists ($namespace, $key)" );

    # Try blobstores in priority order.
    foreach my $bs ( @{$class->_get_blobstores} ) {
        my $rv = $bs->exists( $namespace, $key );
        if ( $rv ) {
            DW::Stats::increment( 'dw.blobstore.action.exists_ok', 1, [ 'store:' . $bs->type ] );
            return $rv;
        } else {
            DW::Stats::increment( 'dw.blobstore.action.exists_failed', 1, [ 'store:' . $bs->type ] );
        }
    }
    $log->info( "Meta-blobstore: file doesn't exist in any store ($namespace, $key)" );
    DW::Stats::increment( 'dw.blobstore.action.exists_error', 1 );
    return 0;
}

1;
