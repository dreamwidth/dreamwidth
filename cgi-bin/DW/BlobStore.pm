#!/usr/bin/perl
#
# DW::BlobStore
#
# Meta storage API for storing arbitrary blobs of content by key.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
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

    # Site owners must configure one of these.
    if ( exists $LJ::BLOBSTORE{s3} ) {
        $log->debug( 'Initializing S3 blobstore.' );
        push @{$blobstores ||= []}, DW::BlobStore::S3->init( %{$LJ::BLOBSTORE{s3}} );
    }
    if ( exists $LJ::BLOBSTORE{localdisk} ) {
        $log->logcroak( 'Must only define a single %LJ::BLOBSTORE entry.' )
            if defined $blobstores;
        $log->debug( 'Initializing localdisk blobstore.' );
        push @{$blobstores ||= []}, DW::BlobStore::LocalDisk->init( %{$LJ::BLOBSTORE{localdisk}} );
    }

    # As a way to support migration of MogileFS data to the new storage
    # system, we support a way of specifying a fallback MogileFS cluster which
    # is activated if we ask for it. This is temporary and will be removed
    # when Dreamwidth is fully off of MogileFS.
    if ( %LJ::MOGILEFS_CONFIG && $LJ::MOGILEFS_CONFIG{hosts} ) {
        $log->debug( 'Initializing MogileFS blobstore.' );
        push @{$blobstores ||= []}, DW::BlobStore::MogileFS->init;
    }

    $log->logcroak( 'Must configure %LJ::BLOBSTORE or %LJ::MOGILEFS_CONFIG.' )
        unless $blobstores;
    $log->debug( 'Blobstore initialized with ', scalar( @$blobstores ), ' blobstores.' );
    return $blobstores;
}

# Check validity of namespace. Dies if invalid.
sub ensure_namespace_is_valid {
    my ( $namespace ) = @_;

    # Ensure that namespace is alpha-numeric
    $log->logcroak( "Namespace '$namespace' is invalid." )
        unless $namespace =~ m!^(?:[a-z][a-z0-9]+)$!;
    return 1;
}

# Check validity of key. Dies if key is invalid.
sub ensure_key_is_valid {
    my ( $key ) = @_;

    # This is just a check to ensure that nobody uses a key without path
    # elements or with invalid characters.
    $log->logcroak( "Key '$key' is invalid." )
        unless $key =~ m!^(?:[a-z0-9]+[_:/-])+([a-z0-9]+)$!;
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
        return $rv if $rv;
    }
    $log->info( "Meta-blobstore: failed to store ($namespace, $key)" );
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
    foreach my $bs ( @{$class->_get_blobstores} ) {
        my $rv = $bs->retrieve( $namespace, $key );
        return $rv if $rv;
    }
    $log->info( "Meta-blobstore: failed to retrieve ($namespace, $key)" );
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
        return $rv if $rv;
    }
    $log->info( "Meta-blobstore: file doesn't exist in any store ($namespace, $key)" );
    return 0;
}

1;
