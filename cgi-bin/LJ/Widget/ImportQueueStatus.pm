#!/usr/bin/perl
#
# LJ::Widget::ImportQueueStatus
#
# Renders a little box showing the status of the importer queue.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package LJ::Widget::ImportQueueStatus;

use strict;
use base qw/ LJ::Widget /;
use Carp qw/ croak /;
use DBI;

sub need_res { qw( stc/importer.css ) }

sub render_body {
    my ( $class, %opts ) = @_;

    my $depth = LJ::MemCache::get('importer_queue_depth');
    unless ($depth) {

        # FIXME: don't make this slam the db with people asking the same question, use a lock
        # FIXME: we don't have ddlockd, maybe we should

        # do manual connection
        my $db  = $LJ::THESCHWARTZ_DBS[0];
        my $dbr = DBI->connect( $db->{dsn}, $db->{user}, $db->{pass} )
            or return "Unable to manually connect to TheSchwartz database.";

        # get the ids for the function map
        my $tmpmap = $dbr->selectall_hashref( 'SELECT funcid, funcname FROM funcmap', 'funcname' );

        # get the counts of jobs in queue (active or not)
        my %cts;
        foreach my $map ( keys %$tmpmap ) {
            next unless $map =~ /^DW::Worker::ContentImporter::LiveJournal::/;

            my $ct = $dbr->selectrow_array(
                q{SELECT COUNT(*) FROM job
                  WHERE funcid = ?
                    AND run_after < UNIX_TIMESTAMP()},
                undef, $tmpmap->{$map}->{funcid}
            ) + 0;

            $map =~ s/^.+::(\w+)$/$1/;
            $cts{ lc $map } = $ct;
        }

        LJ::MemCache::set( 'importer_queue_depth', \%cts, 300 );
        $depth = \%cts;
    }

    # return a very boring little box... this could be improved a lot :)
    my $ret = q{<div class="importer-queue"><strong>Importer Queue Depth:</strong><br />};
    $ret .= join( ', ', map { "$_: " . ( $depth->{ lc $_ } + 0 ) } sort keys %$depth );
    $ret .= q{</div>};
    return $ret;
}

sub should_render {
    return 1;
}

1;
