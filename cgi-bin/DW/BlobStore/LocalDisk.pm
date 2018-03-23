#!/usr/bin/perl
#
# DW::BlobStore::LocalDisk
#
# Implementation of meta-blobstore for storing to local disk. This is a grossly
# inefficient implementation designed to just work.
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

package DW::BlobStore::LocalDisk;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger( __PACKAGE__ );

use Digest::MD5 qw/ md5_hex /;

sub type { 'localdisk' }

sub init {
	my ( $class, %args ) = @_;
	$log->logcroak( 'LocalDisk configuration must include "path" element.' )
		unless exists $args{path};

	mkdir $args{path};
	$log->logcroak( 'LocalDisk{path} is invalid/not a directory.' )
		unless -d $args{path};

	$log->debug( "Initializing blobstore at path: $args{path}" );
	my $self = { path => $args{path} };
	return bless $self, $class;
}

sub get_location_for_key {
	my ( $self, $namespace, $key ) = @_;

	# Hash the key, we create two layers of directory structure so the files
	# spread across 256^2 directories
	my $hash = md5_hex( $key );

	# Ensure path exists
	my $path = $self->{path} . '/' . $namespace;
	mkdir( $path ) unless -d $path;
	$path .= '/' . substr( $hash, 0, 2 );
	mkdir( $path ) unless -d $path;
	$path .= '/' . substr( $hash, 2, 2 );
	mkdir( $path ) unless -d $path;
	$log->logcroak( "Failed to create path: $path" )
		unless -d $path;

	# Return fully qualified filename
	my $fqfn = $path . '/' . $hash;
	$log->debug( "($namespace, $key) => $fqfn" );
	return $fqfn;
}

sub store {
	my ( $self, $namespace, $key, $blobref ) = @_;
	$log->logcroak( 'Unable to store empty file.' )
		unless defined $$blobref && length $$blobref;
	my $fqfn = $self->get_location_for_key( $namespace, $key );

	# Directory should exist now, simply write the file
	my $fh;
	open $fh, '>', $fqfn
		or $log->logcroak( "Failed to open $fqfn: $!" );
	print $fh $$blobref;
	close $fh
		or $log->logcroak( "Failed to close $fqfn: $!" );
	$log->debug( "Wrote ", length $$blobref, " bytes to: $fqfn" );

	# Do sanity check that whole file was written and nothing
	# went wrong in the process
	$log->logcroak( "Just written file doesn't exist: $fqfn" )
		unless -e $fqfn;
	$log->logcroak( "Just written file of wrong size: $fqfn" )
		unless -s $fqfn == length $$blobref;
	return 1;
}

sub exists {
	my ( $self, $namespace, $key ) = @_;
	my $fqfn = $self->get_location_for_key( $namespace, $key );

	# Simple disk presence check
	$log->debug( "Checking disk presence of: $fqfn" );
	return -e $fqfn ? 1 : 0;
}

sub retrieve {
	my ( $self, $namespace, $key ) = @_;
	my $fqfn = $self->get_location_for_key( $namespace, $key );

	# The blobstore assumes files exist, since we should never try to
	# load something we aren't sure exists
	unless ( -e $fqfn ) {
		$log->debug( "File does not exist: $fqfn" );
		return undef;
	}

	# Load file into memory and return
	my ( $fh, $blob );
	open $fh, '<', $fqfn
		or $log->logcroak( "Failed to open for reading: $fqfn" );
	{ local $/ = undef; $blob = <$fh>; }
	close $fh;
	$log->debug( "Read ", length $blob, " bytes from: $fqfn" );
	return \$blob;
}

sub delete {
	my ( $self, $namespace, $key ) = @_;
	my $fqfn = $self->get_location_for_key( $namespace, $key );

	# Can't delete what doesn't exist
	return 0 unless -e $fqfn;

	# Try to remove the file, good-bye
	unlink $fqfn
		or $log->logcroak( "Failed to delete file: $fqfn" );
	$log->debug( "Deleted: $fqfn" );
	return 1;
}

1;
