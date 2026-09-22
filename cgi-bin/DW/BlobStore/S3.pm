#!/usr/bin/perl
#
# DW::BlobStore::S3
#
# Library for storing blobs in S3.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2016-2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::BlobStore::S3;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use Digest::MD5 qw/ md5_hex /;
use Paws;
use Paws::Credential::Explicit;
use URI;

sub type { 's3' }

sub init {
    my ( $class, %args ) = @_;

    %args = $class->validate_config(%args);
    my %config = ( region => $args{region} );
    if ( defined $args{access_key} ) {
        my %credentials = map { $_ => $args{$_} } qw/ access_key secret_key /;
        $credentials{session_token} = $args{session_token} if defined $args{session_token};
        $config{credentials}        = Paws::Credential::Explicit->new(%credentials);
    }

    # Omitting credentials preserves Paws' environment/container/instance role chain.
    my $paws = Paws->new( config => \%config )
        or $log->logcroak('Failed to initialize Paws object.');
    my %service;
    $service{endpoint} = $args{endpoint} if defined $args{endpoint};
    my $s3 = $paws->service( 'S3', %service )
        or $log->logcroak('Failed to initialize Paws::S3 object.');

    $log->debug("Initializing blobstore for S3");
    my $self = {
        s3     => $s3,
        bucket => $args{bucket},
        prefix => $args{prefix}
    };
    return bless $self, $class;
}

# Validate without contacting the storage service (also used by checkconfig).
sub validate_config {
    my ( $class, %args ) = @_;
    $log->logcroak('S3 bucket and bucket_name disagree.')
        if defined $args{bucket}
        && defined $args{bucket_name}
        && $args{bucket} ne $args{bucket_name};
    $args{bucket} //= $args{bucket_name};
    foreach my $required (qw/ region bucket /) {
        $log->logcroak("S3 configuration requires $required.")
            unless defined $args{$required} && length $args{$required};
    }
    $log->logcroak('S3 access_key and secret_key must both be provided or both omitted.')
        if defined $args{access_key} != defined $args{secret_key};
    foreach my $key (qw/ access_key secret_key /) {
        $log->logcroak("S3 $key must not be empty.")
            if defined $args{$key} && !length $args{$key};
    }
    $log->logcroak('S3 session_token requires explicit access_key and secret_key.')
        if defined $args{session_token} && !defined $args{access_key};
    $log->logcroak('Prefix does not match required regex: [a-zA-Z0-9_-]+$.')
        if defined $args{prefix} && $args{prefix} !~ /^[a-zA-Z0-9_-]+$/;
    if ( defined $args{endpoint} ) {
        my $uri = URI->new( $args{endpoint} );
        $log->logcroak(
            'S3 endpoint must be an http(s) URL without credentials, query, or fragment.')
            unless $uri->scheme
            && $uri->scheme =~ /^https?$/
            && $uri->host
            && !defined $uri->userinfo
            && !defined $uri->query
            && !defined $uri->fragment;
        $args{endpoint} =~ s{/$}{};
    }
    return %args;
}

sub get_location_for_key {
    my ( $self, $namespace, $key ) = @_;

    # Hash the key, we create two layers of directory structure so the files
    # spread across 256^2 directories
    my $hash = md5_hex($key);

    # Create the fully qualified path including optional configured prefix
    my $fqfn =
          ( defined $self->{prefix} ? $self->{prefix} . '/' : '' )
        . $namespace . '/'
        . substr( $hash, 0, 2 ) . '/'
        . substr( $hash, 2, 2 ) . '/'
        . $hash;
    $log->debug("($namespace, $key) => $fqfn");
    return $fqfn;
}

sub store {
    my ( $self, $namespace, $key, $blobref ) = @_;
    $log->logcroak('Unable to store empty file.')
        unless defined $$blobref && length $$blobref;
    my $fqfn = $self->get_location_for_key( $namespace, $key );

    my $res = eval {
        $self->{s3}->PutObject(
            Bucket => $self->{bucket},
            Key    => $fqfn,
            Body   => $$blobref,
        );
    };
    if ( $@ && $@->isa('Paws::Exception') ) {
        $log->error( "Failed to store to ( $namespace, $key ): " . $@->message );
        return 0;
    }

    $log->debug( "Wrote ", length $$blobref, " bytes to: $fqfn" );
    return 1;
}

sub exists {
    my ( $self, $namespace, $key ) = @_;
    my $fqfn = $self->get_location_for_key( $namespace, $key );

    my $res = eval { $self->{s3}->HeadObject( Bucket => $self->{bucket}, Key => $fqfn, ) };
    if ( $@ && $@->isa('Paws::Exception') ) {
        $log->error( "Failed to check exists on ( $namespace, $key ): ", $@->message );
        return 0;
    }

    $log->debug( 'Found path exists in S3: ', $fqfn );
    return 1;
}

sub retrieve {
    my ( $self, $namespace, $key ) = @_;
    my $fqfn = $self->get_location_for_key( $namespace, $key );

    my $res = eval { $self->{s3}->GetObject( Bucket => $self->{bucket}, Key => $fqfn, ) };
    if ( $@ && $@->isa('Paws::Exception') ) {
        $log->error( "Failed to retrieve from ( $namespace, $key ): " . $@->message );
        return undef;
    }
    return \$res->Body;
}

sub delete {
    my ( $self, $namespace, $key ) = @_;
    my $fqfn = $self->get_location_for_key( $namespace, $key );

    my $res = eval { $self->{s3}->DeleteObject( Bucket => $self->{bucket}, Key => $fqfn, ) };
    if ( $@ && $@->isa('Paws::Exception') ) {
        $log->error( "Failed to delete ( $namespace, $key ): ", $@->message );
        return 0;
    }

    $log->debug( 'Deleted path from S3: ', $fqfn );
    return 1;
}

1;
