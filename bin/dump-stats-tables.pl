#!/usr/bin/perl
#
# bin/dump-stats-tables.pl
#
# Dumps the tables behind /stats and /stats/site to TSV, for archiving.
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

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use File::Path qw( make_path );
use File::Spec ();

my $dir = shift @ARGV
    or die "Usage: dump-stats-tables.pl <output-directory>\n";

make_path($dir) unless -d $dir;
die "Not a directory: $dir\n" unless -d $dir;

my $dbr = LJ::get_db_reader()
    or die "Failed to get database reader.\n";

# site_stats holds category_id/key_id, both resolved through the same
# statkeylist typemap; joining here keeps the dump readable on its own rather
# than depending on a second file to decode it.
dump_query(
    'stats.tsv',
    [qw( statcat statkey statval )],
    "SELECT statcat, statkey, statval FROM stats ORDER BY statcat, statkey"
);

dump_query(
    'site_stats.tsv',
    [qw( category statkey insert_time value )],
    q{SELECT c.name, k.name, s.insert_time, s.value
      FROM site_stats s
      JOIN statkeylist c ON c.statkeyid = s.category_id
      JOIN statkeylist k ON k.statkeyid = s.key_id
      ORDER BY s.insert_time, c.name, k.name}
);

sub dump_query {
    my ( $filename, $columns, $sql ) = @_;

    my $path = File::Spec->catfile( $dir, $filename );
    open my $fh, '>', $path or die "Failed to open $path: $!\n";

    # mysql_use_result streams from the server; without it DBD::mysql buffers the
    # whole result client-side (~273 MB for site_stats) and the 512 MB cron task
    # is well within OOM range, as get-users-paid already demonstrated.
    my $sth = $dbr->prepare( $sql, { mysql_use_result => 1 } );
    $sth->execute;
    die $dbr->errstr if $dbr->err;

    print $fh join( "\t", @$columns ) . "\n";
    my $rows = 0;
    while ( my $row = $sth->fetchrow_arrayref ) {
        print $fh join( "\t", map { defined $_ ? $_ : '' } @$row ) . "\n";
        $rows++;
    }
    die $dbr->errstr if $dbr->err;

    close $fh or die "Failed to close $path: $!\n";

    die "Refusing to write an empty $filename\n" unless $rows;
    print "-I- $path: $rows rows\n";
}
