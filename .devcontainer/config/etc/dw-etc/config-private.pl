#!/usr/bin/perl

# Private configuration for the .devcontainer; this should work out of the box.
# You should not need to modify this file.
#
# This is where you define private, site-specific configs (e.g. passwords).

use Net::Subnet;

{
    package LJ;

    # Database configuration, this is required to specify what
    # clusters exist. This must map to an appropriate set of roles
    # in %DBINFO.
    @CLUSTERS = ( 1 );

    # Default user creation. Will pick one integer randomly from the
    # arrayref and use it.
    $DEFAULT_CLUSTER = [ 1 ];

    # database info.  only the master is necessary.
    %DBINFO = (
               'master' => {
                   'host' => "127.0.0.1",
                   'port' => 3306,
                   'user' => 'dw',
                   'pass' => 'dw',
                   'dbname' => 'dw_global',
                   'role' => {
                       'slow' => 1,
		       'slave' => 1,
                   },
               },
               'cluster01' => {
                   'host' => "127.0.0.1",
                   'port' => 3306,
                   'user' => 'dw',
                   'pass' => 'dw',
                   'dbname' => 'dw_cluster01',
                   'role' => {
                       'cluster1' => 1,
                   },
               },
    );

    # Schwartz DB configuration
    @THESCHWARTZ_DBS = (
            {
                dsn => 'dbi:mysql:dw_schwartz;host=localhost',
                user => 'dw',
                pass => 'dw',
            },
        );

    # MemCache information, if you have MemCache servers running
    @MEMCACHE_SERVERS = ('127.0.0.1:11211');
    $MEMCACHE_COMPRESS_THRESHOLD = 1_000; # bytes

    # Configuration of BlobStore. This is the new storage abstraction used to
    # store any blobs (images, userpics, media, etc) that need storage. For small
    # sites/single servers, the localdisk mode is useful. For production
    # systems S3 should be used.
    @BLOBSTORES = (
        # Local disk configuration, can be used to store everything on one machine
        localdisk => {
            path => "$LJ::HOME/var/blobstore",
        },
    );
}

1;
