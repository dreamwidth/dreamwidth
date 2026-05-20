#!/usr/bin/perl
#
# DW::Task::ImportEraser
#
# SQS worker that erases imported content.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2012-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::ImportEraser;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::Worker::ContentImporter::Local::Comments;
use DW::Worker::ContentImporter::Local::Entries;

use base 'DW::Task';

sub work {
    my ( $self, $handle ) = @_;

    my %arg = %{ $self->args->[0] };

    # This is a very simple process. Find the user, find all of their importer
    # entries, then delete them one by one. THIS IS VERY DESTRUCTIVE. There is
    # no turning back.
    my $u = LJ::load_userid( $arg{userid} );
    unless ($u) {
        $log->error("Userid can't be loaded. Will retry.");
        return DW::Task::FAILED;
    }

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
    my $p = LJ::get_prop( talk => "import_source" );
    unless ($p) {
        $log->error("Failed to load import_source property.");
        return DW::Task::FAILED;
    }

    my $rows = $u->selectall_arrayref(
        q{SELECT jtalkid, value FROM talkprop2 WHERE journalid = ? AND tpropid = ?},
        undef, $u->id, $p->{id} );
    if ( $u->err ) {
        $log->error( "Database error: " . $u->errstr );
        return DW::Task::FAILED;
    }

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
            if ( $u->err ) {
                $log->error( "Database error: " . $u->errstr );
                return DW::Task::FAILED;
            }
        }
    }

    # Recalculate the number of comments that have been posted.
    LJ::MemCache::delete( [ $u->id, "talk2ct:" . $u->id ] );

    $0 = 'import-eraser: idle';
    return DW::Task::COMPLETED;
}

1;
