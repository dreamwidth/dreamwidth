#!/usr/bin/perl
#
# bin/archive-to-s3.pl
#
# Copies files or directories to the archive bucket, under <prefix>/<date>/.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use File::Find ();
use File::Spec ();
use POSIX qw( strftime );
use Paws;

my ( $prefix, @paths ) = @ARGV;

die "Usage: archive-to-s3.pl <prefix> <path> [<path>...]\n"
    unless defined $prefix && @paths;

my $bucket = $ENV{ARCHIVE_BUCKET}
    or die "ARCHIVE_BUCKET is not set.\n";

# UTC to match the cron schedules; a local timezone would skip or collide a day
# around DST, and the date is part of the object key.
my $date = strftime( '%Y-%m-%d', gmtime );

my $s3 = Paws->new( config => { region => $ENV{ARCHIVE_REGION} || 'us-east-1' } )->service('S3');

foreach my $arg (@paths) {
    my $path =
        File::Spec->file_name_is_absolute($arg)
        ? $arg
        : File::Spec->catfile( $ENV{LJHOME}, $arg );
    $path =~ s{/+$}{};

    die "No such file or directory: $path\n" unless -e $path;

    if ( -d $path ) {
        my @files;
        File::Find::find(
            {
                no_chdir => 1,
                wanted   => sub { push @files, $File::Find::name if -f $File::Find::name },
            },
            $path
        );
        my $base = ( File::Spec->splitdir($path) )[-1];
        upload( $_, "$base/" . File::Spec->abs2rel( $_, $path ) ) foreach sort @files;
    }
    else {
        upload( $path, ( File::Spec->splitpath($path) )[2] );
    }
}

sub upload {
    my ( $path, $name ) = @_;

    open my $fh, '<', $path or die "Failed to open $path: $!\n";
    binmode $fh;
    my $body = do { local $/; <$fh> };
    close $fh;

    my $key = "$prefix/$date/$name";

    # Die rather than warn: a non-zero exit is what the cron failure alarm keys
    # on, and a silently skipped archive is the failure we care about.
    eval {
        $s3->PutObject( Bucket => $bucket, Key => $key, Body => $body );
        1;
    } or die "Failed to upload $path to s3://$bucket/$key: $@\n";

    print "-I- s3://$bucket/$key\n";
}
