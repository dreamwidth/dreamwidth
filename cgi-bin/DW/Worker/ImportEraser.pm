#!/usr/bin/perl
#
# DW::Worker::ImportEraser
#
# Erases imported content.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use v5.10;
use strict;
use warnings;

package DW::Worker::ImportEraser;
use base 'TheSchwartz::Worker';
use DW::Worker::ContentImporter::Local::Entries;
use DW::Worker::ContentImporter::Local::Comments;

sub schwartz_capabilities { 'DW::Worker::ImportEraser' }
sub max_retries           { 5 }
sub retry_delay           { ( 30, 120, 300, 600, 900 )[ $_[1] ] }
sub keep_exit_status_for  { 86400 }                                 # 24 hours
sub grab_for              { 3600 }

sub work {
    my ( $class, $job ) = @_;
    my %arg = %{ $job->arg };

    # This is a very simple process. Find the user, find all of their importer
    # entries, then delete them one by one. THIS IS VERY DESTRUCTIVE. There is
    # no turning back.
    my $u = LJ::load_userid( $arg{userid} )
        or return $job->failed("Userid can't be loaded. Will retry.");
    my %map = %{ DW::Worker::ContentImporter::Local::Entries->get_entry_map($u) || {} };
    my ( $ct, $max ) = ( 0, scalar keys %map );
    foreach my $jitemid ( values %map ) {
        $ct++;
        $0 = sprintf( "import-eraser: %s(%d) - entry %d/%d - %0.2f%%",
            $u->user, $u->userid, $ct, $max, $ct / $max * 100 );
        LJ::delete_entry( $u, $jitemid, 0, undef );
    }

    # Now get the comment map, in case anything didn't get totally deleted. We
    # have to do this like this because in some rare failure cases, we have
    # comments that map to the same broken values.
    my $p = LJ::get_prop( talk => "import_source" )
        or return $job->failed("Failed to load import_source property.");
    my $rows = $u->selectall_arrayref(
        q{SELECT jtalkid, value FROM talkprop2 WHERE journalid = ? AND tpropid = ?},
        undef, $u->id, $p->{id} );
    return $job->failed( "Database error: " . $u->errstr )
        if $u->err;

    ( $ct, $max ) = ( 0, scalar @$rows );
    foreach my $row (@$rows) {
        my ( $jtalkid, $value ) = @$row;

        $ct++;
        $0 = sprintf( "import-eraser: %s(%d) - comment %d/%d - %0.2f%%",
            $u->user, $u->userid, $ct, $max, $ct / $max * 100 );

        # There is no method for deleting these items, so we just have to do it
        # manually.
        foreach my $table (qw/ talk2 talkprop2 talktext2 /) {
            $u->do( qq{DELETE FROM $table WHERE journalid = ? AND jtalkid = ?},
                undef, $u->id, $jtalkid );
            return $job->failed( "Database error: " . $u->errstr )
                if $u->err;
        }
    }

    # Recalculate the number of comments that have been posted.
    LJ::MemCache::delete( [ $u->id, "talk2ct:" . $u->id ] );

    $job->completed;
    $0 = 'import-eraser: idle';
}

1;
