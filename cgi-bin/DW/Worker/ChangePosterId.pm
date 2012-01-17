#!/usr/bin/perl
#
# DW::Worker::ChangePosterId
#
# Does the heavy lifting of changing a poster.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2012 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

package DW::Worker::ChangePosterId;
use base 'TheSchwartz::Worker';
use LJ::User;

sub schwartz_capabilities { return ('DW::Worker::ChangePosterId'); }
sub max_retries { 5 }
sub retry_delay { return (10, 30, 60, 300, 600)[$_[1]]; }
sub keep_exit_status_for { 86400 }
sub grab_for { 86400 }

sub work {
    my ( $class, $job ) = @_;

    my %arg = %{$job->arg};
    my $fu = LJ::load_userid( delete $arg{from_userid} );
    my $tu = LJ::load_userid( delete $arg{to_userid} );
    return $job->failed( 'Failed to load the involved users.' )
        unless $fu && $tu;
    return $job->permanent_failure( 'Unknown keys: ' . join( ', ', keys %arg ))
        if keys %arg;
    return $job->permanent_failure( 'Makes no sense! The users are the same?!' )
        if $fu->id == $tu->id;

    # Basically, all this job is doing is reparenting comments and posts that
    # have been made by a particular user. We try to be gentle to the database by
    # only updating a few rows at a time, but there's no way this isn't going to
    # pound the system on large users. Memcache complicates things, too, since we
    # might cache things and then update them underneath it.

    foreach my $cid ( @LJ::CLUSTERS ) {
        my $dbcm = LJ::get_cluster_master( $cid )
            or return $job->failed( "Temporary failure connecting to cluster $cid." );

        eval {
            fix_entries( $dbcm, $fu, $tu );
            fix_comments( $dbcm, $fu, $tu );
        };
        return $job->failed( "Temporary failure fixing things: $@" ) if $@;
    }
    $job->completed;

    # we're done and happy
    $0 = 'change-poster-id [bored]';
}

sub fix_entries {
    my ( $dbcm, $fu, $tu ) = @_;

    my $total = $dbcm->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE posterid = ?', undef, $fu->id );
    title( $fu, $tu, 'entries', 0, $total );

    my $ct = 0;
    while ( 1 ) {
        my $rows = $dbcm->selectall_arrayref(
            'SELECT journalid, jitemid FROM log2 WHERE posterid = ? LIMIT 100',
            undef, $fu->id
        );
        die $dbcm->errstr if $dbcm->err;
        last unless $rows && @$rows;

        foreach my $row ( @$rows ) {
            my ( $jid, $jitemid ) = @$row;

            $ct++;
            title( $fu, $tu, 'entries', $ct, $total );

            # update the db
            $dbcm->do( 'UPDATE log2 SET posterid = ? ' .
                'WHERE journalid = ? AND jitemid = ? AND posterid = ? LIMIT 1',
                undef, $tu->id, $jid, $jitemid, $fu->id
            );
            die $dbcm->errstr if $dbcm->err;

            # now nuke the memcache
            LJ::MemCache::delete( [ $jid, "log2:$jid:$jitemid" ] );
            LJ::MemCache::delete( [ $jid, "log2lt:$jid" ] );
        }
    }
}

sub fix_comments {
    my ( $dbcm, $fu, $tu ) = @_;

    my $total = $dbcm->selectrow_array( 'SELECT COUNT(*) FROM talk2 WHERE posterid = ?', undef, $fu->id );
    title( $fu, $tu, 'comments', 0, $total );

    my $ct = 0;
    while ( 1 ) {
        my $rows = $dbcm->selectall_arrayref(
            'SELECT journalid, jtalkid, nodetype, nodeid ' .
            'FROM talk2 WHERE posterid = ? LIMIT 100',
            undef, $fu->id
        );
        die $dbcm->errstr if $dbcm->err;
        last unless $rows && @$rows;

        foreach my $row ( @$rows ) {
            my ( $jid, $jtalkid, $nodetype, $nodeid ) = @$row;

            $ct++;
            title( $fu, $tu, 'comments', $ct, $total );

            # update the db
            $dbcm->do( 'UPDATE talk2 SET posterid = ? ' .
                'WHERE journalid = ? AND jtalkid = ? AND posterid = ? LIMIT 1',
                undef, $tu->id, $jid, $jtalkid, $fu->id
            );
            die $dbcm->errstr if $dbcm->err;

            # now nuke the memcache
            LJ::MemCache::delete( [ $jid, "talk2:$jid:$nodetype:$nodeid" ] );
            LJ::MemCache::delete( [ $jid, "talk2row:$jid:$jtalkid" ] );
        }
    }

    # fix the "comments posted" entry on the profile
    LJ::MemCache::delete( [ $fu->id, "talkleftct:" . $fu->id ] );
    LJ::MemCache::delete( [ $tu->id, "talkleftct:" . $tu->id ] );
}

sub title {
    my ( $fu, $tu, $which, $cur, $total ) = @_;
    my $title = sprintf( 'change-poster-id [%s :: %s -> %s :: %d/%d :: %0.2f%%]',
            $which, $fu->display_name, $tu->display_name, $cur, $total, $cur/$total*100 );
    $0 = $title;
}

1;
