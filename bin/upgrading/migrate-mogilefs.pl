#!/usr/bin/perl
#
# bin/upgrading/migrate-mogilefs.pl
#
# Move files out of a MogileFS cluster and into the current BlobStore
# primary storage.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use v5.10;
use strict;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use Carp qw/ croak /;
use DBI;
use Getopt::Long;
use MogileFS::Client;

use DW::BlobStore;

use constant BLOCK_SIZE => 1_000;

my ( $startfid, $endfid, $max_workers, $conf );
GetOptions(
    'start-fid=i'       => \$startfid,
    'end-fid=i'         => \$endfid,
    'num-workers=i'     => \$max_workers,
    'mogilefs-config=s' => \$conf,
);
$startfid ||= 0;
$endfid ||= 1_000_000_000;
$max_workers ||= 10;

die "Must provide valid --mogilefs-config=FILEPATH argument.\n"
    unless $conf && -e $conf;

my $mogc = get_mogilefs_client();

my $queue = [];
my $cur_workers = 0;
my $num_workers = 0;
my $enqueued = 0;
while ( $startfid <= $endfid ) {
    my $files = get_files( $startfid, $startfid + ( BLOCK_SIZE - 1 ) );
    $startfid += BLOCK_SIZE;
    next unless $files;

    foreach my $fid ( keys %$files ) {
        $enqueued++;
        push @$queue, $files->{$fid};
        next if scalar @$queue < BLOCK_SIZE;

        $0 = sprintf( 'migrate-mogilefs: enqueued %d, workers %d',
                $enqueued, $num_workers );

        if ( $cur_workers >= $max_workers ) {
            wait;
            $cur_workers--;
        }

        make_worker( $queue );

        $num_workers++;
        $cur_workers++;
        $queue = [];
    }
}

if ( $queue && @$queue ) {
    make_worker( $queue );
    $cur_workers++;
}

while ( $cur_workers > 0 ) {
    wait;
    $cur_workers--;
}
say "All done.";

sub make_worker {
    my $queue = $_[0];

    if ( my $pid = fork ) {
        return;
    }

    my $pos = 0;
    my $llen = scalar @$queue;
    foreach my $file ( @$queue ) {
        $pos++;
        $0 = sprintf( 'migrate-mogilefs [%d/%d] = %0.2f%%',
            $pos, $llen, 100*($pos/$llen) );

        # Quick check to make sure this file isn't already in BlobStore
        if ( DW::BlobStore->exists( $file->{class} => $file->{key} ) ) {
            say "$file->{fid}: OK EXISTS";
            next;
        }

        my $data = $mogc->get_file_data( $file->{key} );
        unless ( $data ) {
            say "$file->{fid}: ERR NODATA";
            next;
        }

        my $size = length $$data;
        unless ( $size == $file->{size} ) {
            say "$file->{fid}: ERR WRONGSIZE $size $file->{size}";
            next;
        }

        # It's a file and the length is write, let's store it to BlobStore with the
        # right data...
        my $rv = DW::BlobStore->store( $file->{class} => $file->{key}, $data );
        if ( $rv ) {
            say "$file->{fid}: OK STORE";
        } else {
            say "$file->{fid}: ERR STORE";
        }
    }

    exit;
}

sub get_files {
    my ( $start_fid, $end_fid ) = @_;

    my $dbh = get_mogilefs_dbh();

    my $rows = $dbh->selectall_arrayref(
        q{SELECT f.fid, f.dkey, f.length, d.namespace, c.classname
          FROM file f, domain d, class c
          WHERE f.fid >= ? AND f.fid <= ? AND
                d.dmid = f.dmid AND c.dmid = f.dmid AND c.classid = f.classid
        },
        undef, $start_fid, $end_fid,
    );
    return undef unless $rows && scalar @$rows;

    my $out = {};
    foreach my $row ( @$rows ) {
        $out->{$row->[0]} = {
            fid    => $row->[0],
            key    => $row->[1],
            size   => $row->[2],
            domain => $row->[3],
            class  => $row->[4],
        };
    }
    return $out;
}

sub get_mogilefs_dbh {
    my %config;
    open FILE, "<$conf" or die;
    foreach my $line ( <FILE> ) {
        my ( $key, $val ) = ( $1, $2 )
            if $line =~ /^db_(\w+)\s*=\s*(.+?)$/;
        next unless $key && $val;

        $config{$key} = $val;
    }
    close FILE;

    my $dbh = DBI->connect($config{dsn}, $config{user}, $config{pass})
        or die "Failed to connect to MogileFS.\n";
    return $dbh;
}

sub get_mogilefs_client {
    my $mogclient = MogileFS::Client->new(
       domain   => $LJ::MOGILEFS_CONFIG{domain},
       root     => $LJ::MOGILEFS_CONFIG{root},
       hosts    => $LJ::MOGILEFS_CONFIG{hosts},
       timeout  => $LJ::MOGILEFS_CONFIG{timeout},
   )
        or die "Failed to create MogileFS::Client!\n";
    return $mogclient;
}
