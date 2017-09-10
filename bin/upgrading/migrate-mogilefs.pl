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

my ( $nextfid, $endfid, $conf );
GetOptions(
    'start-fid=i'       => \$nextfid,
    'end-fid=i'         => \$endfid,
    'mogilefs-config=s' => \$conf,
);
$nextfid ||= 0;
$endfid ||= 1_000_000_000;

die "Must provide valid --mogilefs-config=FILEPATH argument.\n"
    unless $conf && -e $conf;

my $dbh = get_mogilefs_dbh();
my $mogc = get_mogilefs_client();

# Main loop; just get some files and do cool things with them. In essence we're just getting
# them from MogileFS and storing them to BlobStore.
while ( 1 ) {
    my $files = get_some_files( $dbh, $nextfid+1, $endfid );
    if ( ! defined $files ) {
        say "Looks like we're done, good-bye!";
        exit;
    }

    foreach my $fid ( keys %$files ) {
        $nextfid = $fid if $fid > $nextfid;

        # Quick check to make sure this file isn't already in BlobStore
        if ( DW::BlobStore->exists( $files->{$fid}->{class} => $files->{$fid}->{key} ) ) {
            say "$fid: OK EXISTS";
            next;
        }

        my $data = $mogc->get_file_data( $files->{$fid}->{key} );
        unless ( $data ) {
            say "$fid: ERR NODATA";
            next;
        }

        my $size = length $$data;
        unless ( $size == $files->{$fid}->{size} ) {
            say "$fid: ERR WRONGSIZE $size $files->{$fid}->{size}";
            next;
        }

        # It's a file and the length is write, let's store it to BlobStore with the
        # right data...
        my $rv = DW::BlobStore->store( $files->{$fid}->{class} => $files->{$fid}->{key}, $data );
        if ( $rv ) {
            say "$fid: OK STORE";
        } else {
            say "$fid: ERR STORE";
        }
    }
}

sub get_some_files {
    my ( $dbh, $start_fid, $end_fid ) = @_;

    my $rows = $dbh->selectall_arrayref(
        q{SELECT f.fid, f.dkey, f.length, d.namespace, c.classname
          FROM file f, domain d, class c
          WHERE f.fid >= ? AND f.fid < ? AND
                d.dmid = f.dmid AND c.dmid = f.dmid AND c.classid = f.classid
          ORDER BY f.fid
          LIMIT 100},
        undef, $start_fid, $end_fid,
    );
    return undef unless $rows && scalar @$rows;

    my $out = {};
    foreach my $row ( @$rows ) {
        $out->{$row->[0]} = {
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
