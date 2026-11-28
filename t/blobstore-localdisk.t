# t/blobstore-localdisk.t
#
# Test the local disk blob store without loading the site bootstrap.
#
# Authors:
#      Alex <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use lib "$ENV{LJHOME}/extlib/lib/perl5", "$ENV{LJHOME}/cgi-bin";

use File::Temp qw/ tempdir tempfile /;
use Log::Log4perl qw/ :levels /;
use Test::Exception;
use Test::More;

use DW::BlobStore::LocalDisk;

Log::Log4perl->easy_init($OFF);

my $root = tempdir( CLEANUP => 1 );
my $path = "$root/blobs";
my $key  = 'objects/example';

subtest 'storage directory configuration' => sub {
    throws_ok { DW::BlobStore::LocalDisk->init } qr/must include .*path/,
        'missing storage path is rejected';

    my ( $file, $filename ) = tempfile( DIR => $root );
    close $file or die "Cannot close $filename: $!";
    throws_ok { DW::BlobStore::LocalDisk->init( path => $filename ) } qr/not a directory/,
        'regular file cannot be used as the storage directory';

    DW::BlobStore::LocalDisk->init( path => $path );
    ok( -d $path, 'initialization creates the storage directory' );
};

subtest 'binary blobs persist across instances and stay isolated by namespace' => sub {
    my $store = DW::BlobStore::LocalDisk->init( path => $path );
    my $blob  = "\x00first\nsecond\xff\x00";
    my $other = 'other namespace';

    is( $store->exists( media => $key ),   0,     'unwritten key does not exist' );
    is( $store->retrieve( media => $key ), undef, 'reading an unwritten key returns undef' );
    is( $store->delete( media => $key ),   0,     'deleting an unwritten key returns false' );

    ok( $store->store( media   => $key, \$blob ),  'stores a binary blob' );
    ok( $store->store( archive => $key, \$other ), 'stores the same key in another namespace' );
    ok(
        -f "$path/media/09/14/09143b07daea681d5eb37dc932ff3598",
        'blob is stored at its persistent sharded location'
    );

    my $reopened = DW::BlobStore::LocalDisk->init( path => $path );
    is( $reopened->exists( media => $key ), 1, 'a fresh instance sees the stored key' );
    is_deeply( $reopened->retrieve( media => $key ), \$blob, 'all binary bytes survive reopening' );

    my $shorter = '0';
    ok(
        $reopened->store( media => $key, \$shorter ),
        'overwrites with a shorter, false-valued blob'
    );
    is_deeply( $store->retrieve( media => $key ), \$shorter, 'overwrite leaves no trailing bytes' );

    is( $reopened->delete( media => $key ), 1,     'stored blob can be deleted' );
    is( $store->exists( media => $key ),    0,     'deleted key no longer exists' );
    is( $store->retrieve( media => $key ),  undef, 'deleted blob cannot be read' );
    is( $store->delete( media => $key ),    0,     'deleting the same key again returns false' );
    is_deeply( $store->retrieve( archive => $key ),
        \$other, 'overwrite and deletion leave the other namespace intact' );
};

subtest 'invalid writes do not overwrite existing data' => sub {
    my $store = DW::BlobStore::LocalDisk->init( path => $path );
    my $blob  = 'keep this';
    my $empty = '';
    my $undefined;

    ok( $store->store( media => $key, \$blob ), 'stores the original blob' );
    throws_ok { $store->store( media => $key, \$empty ) } qr/empty file/,
        'rejects an empty replacement';
    throws_ok { $store->store( media => $key, \$undefined ) } qr/empty file/,
        'rejects an undefined replacement';
    is_deeply( $store->retrieve( media => $key ), \$blob, 'both rejections preserve the original' );
};

subtest 'filesystem collisions surface storage errors' => sub {
    my $store    = DW::BlobStore::LocalDisk->init( path => $path );
    my $location = $store->get_location_for_key( media => 'objects/collision' );
    mkdir $location or die "Cannot create $location: $!";

    my $blob = 'cannot write this';
    throws_ok { $store->store( media => 'objects/collision', \$blob ) } qr/Failed to open/,
        'storing fails when the destination is a directory';
    throws_ok { $store->delete( media => 'objects/collision' ) } qr/Failed to delete/,
        'deletion fails rather than removing the directory';
    ok( -d $location, 'the colliding directory remains' );
};

done_testing;
