#!/usr/bin/perl
#
# DW::BlobStore::MogileFS
#
# Implementation of meta-blobstore for storing to MogileFS. This is just a shim
# designed for migration away from MogileFS.
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

package DW::BlobStore::MogileFS;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Digest::MD5 qw/ md5_hex /;

sub type { 'mogilefs' }

sub init {
    my ( $class, %args ) = @_;

    eval 'use MogileFS::Client;';
    $log->logcroak("Couldn't load MogileFS: $@")
        if $@;

    my $mogclient = MogileFS::Client->new(
        domain  => $args{domain},
        root    => $args{root},
        hosts   => $args{hosts},
        timeout => $args{timeout},
    ) or $log->logcroak('Could not initialize MogileFS');

    $log->debug('Initialized MogileFS blobstore');
    return bless { mogclient => $mogclient }, $class;
}

sub store {
    my ( $self, $namespace, $key, $blobref ) = @_;
    $log->logcroak('Unable to store empty file.')
        unless defined $$blobref && length $$blobref;

    my $fh = $self->{mogclient}->new_file( $key, $namespace )
        or $log->logcroak("Failed to create file in MogileFS: ($namespace, $key)");
    $fh->print($$blobref);
    my $rv = $fh->close;
    $log->debug( "Wrote " . length($$blobref) . " bytes to MogileFS for key: $key [rv=$rv]" );
    return $rv;
}

sub exists {
    my ( $self, $namespace, $key ) = @_;

    # Note: Due to the way MogileFS works, the namespace is not used for
    # retrieving files since keys are globally unique.
    # Just check if any paths exist to see if the file exists
    my @paths = $self->{mogclient}->get_paths($key);
    $log->debug( "Found ", scalar(@paths), " paths from MogileFS for key: ", $key );
    return scalar @paths > 0 ? 1 : 0;
}

sub retrieve {
    my ( $self, $namespace, $key ) = @_;

    # Note: Due to the way MogileFS works, the namespace is not used for
    # retrieving files since keys are globally unique.
    my $data = $self->{mogclient}->get_file_data($key);
    if ( defined $data && ref $data eq 'SCALAR' ) {
        $log->debug( "Read " . length($$data) . " bytes from MogileFS for key: $key" );
        return $data;
    }
    $log->info("Read failed to find MogileFS file: $key");
    return undef;
}

sub delete {
    my ( $self, $namespace, $key ) = @_;

    # Note: Due to the way MogileFS works, the namespace is not used for
    # retrieving files since keys are globally unique.
    my $rv = $self->{mogclient}->delete($key);
    $log->debug("Deleted from MogileFS: $key [rv=$rv]");
    return $rv ? 1 : 0;
}

1;
