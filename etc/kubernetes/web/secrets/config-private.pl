#!/usr/bin/perl
{
    package LJ;

    # database info.  only the master is necessary.
    %DBINFO = (
               'master' => {  # master must be named 'master'
                   'host' => 'mysql',
                   'port' => 3306,
                   'user' => 'root',
                   'pass' => 'password',
                   'dbname' => 'dw_global',
                   'role' => {
                       'slow' => 1,
                   },
               },
               'cluster1' => {
                   'host' => 'mysql',
                   'port' => 3306,
                   'user' => 'root',
                   'pass' => 'password',
                   'dbname' => 'dw_cluster1',
                   'role' => {
                       'cluster1' => 1,
                   },
               },
    );

    # Schwartz DB configuration
    @THESCHWARTZ_DBS = (
            {
                dsn => 'dbi:mysql:dw_schwartz;host=mysql',
                user => 'root',
                pass => 'password',
            },
        );

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
