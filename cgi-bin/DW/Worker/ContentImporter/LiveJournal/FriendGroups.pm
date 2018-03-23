#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal::FriendGroups
#
# Importer worker for LiveJournal-based sites friend groups.
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::ContentImporter::LiveJournal::FriendGroups;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

use Carp qw/ croak confess /;
use Storable qw/ nfreeze /;
use DW::Worker::ContentImporter::Local::TrustGroups;

sub work {

    # VITALLY IMPORTANT THAT THIS IS CLEARED BETWEEN JOBS
    %DW::Worker::ContentImporter::LiveJournal::MAPS = ();

    my ( $class, $job ) = @_;
    my $opts = $job->arg;
    my $data = $class->import_data( $opts->{userid}, $opts->{import_data_id} );

    return $class->decline( $job ) unless $class->enabled( $data );

    eval { try_work( $class, $job, $opts, $data ); };
    if ( my $msg = $@ ) {
        $msg =~ s/\r?\n/ /gs;
        return $class->temp_fail( $data, 'lj_friendgroups', $job, 'Failure running job: %s', $msg );
    }
}

sub try_work {
    my ( $class, $job, $opts, $data ) = @_;

    # failure wrappers for convenience
    my $fail      = sub { return $class->fail( $data, 'lj_friendgroups', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_friendgroups', $job ); };
    my $temp_fail = sub { return $class->temp_fail( $data, 'lj_friendgroups', $job, @_ ); };

    # setup
    my $u = LJ::load_userid( $data->{userid} )
        or return $fail->( 'Unable to load target with id %d.', $data->{userid} );
    $0 = sprintf( 'content-importer [friendgroups: %s(%d)]', $u->user, $u->id );

    my $dbh = LJ::get_db_writer()
        or return $temp_fail->( 'Unable to get global master database handle' );

    my $r = $class->call_xmlrpc( $data, 'getfriends', { includegroups => 1 } );
    my $xmlrpc_fail = 'XMLRPC failure: ' . ( $r ? $r->{faultString} : '[unknown]' );
    $xmlrpc_fail .=  " (community: $data->{usejournal})" if $data->{usejournal};
    return $temp_fail->( $xmlrpc_fail ) if ! $r || $r->{fault};

    my $map = DW::Worker::ContentImporter::Local::TrustGroups->merge_trust_groups( $u, $r->{friendgroups} );

    # store the merged map
    $dbh->do(
        q{UPDATE import_data SET groupmap = ?
          WHERE userid = ? AND import_data_id = ?},
        undef, nfreeze( $map ), $u->id, $opts->{import_data_id}
    );

    # mark lj_friends item as able to be scheduled now, and save the map
# FIXME: what do we do on error case? well, hopefully that will be rare...
    $dbh->do(
        q{UPDATE import_items SET status = 'ready'
          WHERE userid = ? AND item IN ('lj_friends', 'lj_entries')
          AND import_data_id = ? AND status = 'init'},
        undef, $u->id, $opts->{import_data_id}
    );

    return $ok->();
}


1;
