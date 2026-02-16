#!/usr/bin/perl
#
# DW::Task::SynSuck
#
# Worker for syndicated feed updates.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::SynSuck;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use LJ::SynSuck;

use base 'DW::Task';

sub work {
    my ( $self, $handle ) = @_;

    my $a = $self->args->[0];

    my $u = LJ::load_userid( $a->{userid} );
    unless ($u) {
        $log->error("Invalid userid: $a->{userid}.");
        return DW::Task::COMPLETED;
    }

    my $dbh = LJ::get_db_writer();
    unless ($dbh) {
        $log->warn("Unable to connect to global database.");
        return DW::Task::FAILED;
    }

    $log->info( sprintf( "SynSuck worker started for %s(%d).", $u->user, $u->id ) );

    my $row = $dbh->selectrow_hashref(
        q{SELECT u.user, s.userid, s.synurl, s.lastmod, s.etag, s.numreaders, s.checknext
          FROM user u, syndicated s
          WHERE u.userid = s.userid AND s.userid = ?},
        undef, $u->id
    );
    if ( $dbh->err ) {
        $log->error( $dbh->errstr );
        return DW::Task::FAILED;
    }
    unless ($row) {
        $log->error("Unable to get syndicated row.");
        return DW::Task::COMPLETED;
    }

    eval { LJ::SynSuck::update_feed($row); };
    if ($@) {
        $log->error("Exception updating feed for userid $a->{userid}: $@");

        # Push checknext into the future so the scheduler doesn't
        # immediately re-enqueue this broken feed.  Unhandled exceptions
        # bypass the normal delay() calls inside SynSuck, so without
        # this the feed would spin in a tight retry loop.
        LJ::SynSuck::delay( $a->{userid}, 6 * 60, "exception" );
        return DW::Task::COMPLETED;
    }

    return DW::Task::COMPLETED;
}

1;
