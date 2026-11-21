#!/usr/bin/perl
#
# DW::Task::ChangePosterId
#
# SQS worker that does the heavy lifting of changing a poster (reparenting
# entries and comments from one user to another across all DB clusters).
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

package DW::Task::ChangePosterId;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use LJ::User;

use base 'DW::Task';

sub work {
    my ( $self, $handle ) = @_;

    my %arg = %{ $self->args->[0] };
    my $fu  = LJ::load_userid( delete $arg{from_userid} );
    my $tu  = LJ::load_userid( delete $arg{to_userid} );

    unless ( $fu && $tu ) {
        $log->error('Failed to load the involved users.');
        return DW::Task::FAILED;
    }
    if ( keys %arg ) {
        $log->error( 'Unknown keys: ' . join( ', ', keys %arg ) );
        return DW::Task::COMPLETED;
    }
    if ( $fu->id == $tu->id ) {
        $log->error('Makes no sense! The users are the same?!');
        return DW::Task::COMPLETED;
    }
    unless ( $fu->dversion >= 9 && $tu->dversion >= 9 ) {
        $log->error('Both users must be dversion 9+ to use this.');
        return DW::Task::COMPLETED;
    }

    # Basically, all this job is doing is reparenting comments and posts that
    # have been made by a particular user. We try to be gentle to the database by
    # only updating a few rows at a time, but there's no way this isn't going to
    # pound the system on large users. Memcache complicates things, too, since we
    # might cache things and then update them underneath it.

    foreach my $cid (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($cid);
        unless ($dbcm) {
            $log->error("Temporary failure connecting to cluster $cid.");
            return DW::Task::FAILED;
        }

        eval {
            fix_entries( $dbcm, $fu, $tu );
            fix_comments( $dbcm, $fu, $tu );
        };
        if ($@) {
            $log->error("Temporary failure fixing things: $@");
            return DW::Task::FAILED;
        }
    }

    eval { fix_talkleft( $fu, $tu ); };
    if ($@) {
        $log->error("Temporary failure fixing talkleft: $@");
        return DW::Task::FAILED;
    }

    # we're done and happy
    $0 = 'change-poster-id [bored]';
    return DW::Task::COMPLETED;
}

sub fix_entries {
    my ( $dbcm, $fu, $tu ) = @_;

    my $total =
        $dbcm->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE posterid = ?', undef, $fu->id );
    die $dbcm->errstr if $dbcm->err;
    return unless $total > 0;
    title( $fu, $tu, 'entries', 0, $total );

    # we need these ids
    my $p_id = LJ::get_prop( log => 'picture_mapid' )->{id};
    die "Unable to load property ID.\n"
        unless $p_id;

    my $ct = 0;
    while (1) {
        my $rows = $dbcm->selectall_arrayref(
            'SELECT journalid, jitemid FROM log2 WHERE posterid = ? LIMIT 100',
            undef, $fu->id );
        die $dbcm->errstr if $dbcm->err;
        last unless $rows && @$rows;

        foreach my $row (@$rows) {
            my ( $jid, $jitemid ) = @$row;
            my $u = LJ::load_userid($jid);
            die "Failed to load user object for location.\n" unless $u;

            $ct++;
            title( $fu, $tu, 'entries', $ct, $total );

            # update the db
            $dbcm->do(
                'UPDATE log2 SET posterid = ? '
                    . 'WHERE journalid = ? AND jitemid = ? AND posterid = ? LIMIT 1',
                undef, $tu->id, $jid, $jitemid, $fu->id
            );
            die $dbcm->errstr if $dbcm->err;

            # fix the pictures on this post
            my $mapid = $dbcm->selectrow_array(
                'SELECT value FROM logprop2 '
                    . 'WHERE journalid = ? AND jitemid = ? AND propid = ?',
                undef, $jid, $jitemid, $p_id
            );
            die $dbcm->errstr if $dbcm->err;

            # but only if it exists... and it should always be 1+ due to how we use
            # the usercounters
            if ( defined $mapid && $mapid > 0 ) {
                my $kw = $fu->get_keyword_from_mapid($mapid)
                    || $u->get_keyword_from_mapid($mapid);
                if ($kw) {
                    my $newid = $tu->get_mapid_from_keyword( $kw, create => 1 );
                    die "Failed to allocate new picture_mapid.\n"
                        unless defined $newid && $newid > 0;

                    $dbcm->do(
                        'UPDATE logprop2 SET value = ? '
                            . 'WHERE journalid = ? AND jitemid = ? AND propid = ?',
                        undef, $newid, $jid, $jitemid, $p_id
                    );
                    die $dbcm->errstr if $dbcm->err;
                }
            }

            # now nuke the memcache
            LJ::MemCache::delete( [ $jid, "log2:$jid:$jitemid" ] );
            LJ::MemCache::delete( [ $jid, "log2lt:$jid" ] );
            LJ::MemCache::delete( [ $jid, "logprop:$jid:$jitemid" ] );
        }
    }
}

sub fix_comments {
    my ( $dbcm, $fu, $tu ) = @_;

    my $total =
        $dbcm->selectrow_array( 'SELECT COUNT(*) FROM talk2 WHERE posterid = ?', undef, $fu->id );
    die $dbcm->errstr if $dbcm->err;
    return unless $total > 0;
    title( $fu, $tu, 'comments', 0, $total );

    # we need these ids
    my $p_id = LJ::get_prop( talk => 'picture_mapid' )->{id};
    die "Unable to load property ID.\n"
        unless $p_id;

    my $ct = 0;
    while (1) {
        my $rows = $dbcm->selectall_arrayref(
            'SELECT journalid, jtalkid, nodetype, nodeid '
                . 'FROM talk2 WHERE posterid = ? LIMIT 100',
            undef, $fu->id
        );
        die $dbcm->errstr if $dbcm->err;
        last unless $rows && @$rows;

        foreach my $row (@$rows) {
            my ( $jid, $jtalkid, $nodetype, $nodeid ) = @$row;
            my $u = LJ::load_userid($jid);
            die "Failed to load user object for location.\n" unless $u;

            $ct++;
            title( $fu, $tu, 'comments', $ct, $total );

            # update the db
            $dbcm->do(
                'UPDATE talk2 SET posterid = ? '
                    . 'WHERE journalid = ? AND jtalkid = ? AND posterid = ? LIMIT 1',
                undef, $tu->id, $jid, $jtalkid, $fu->id
            );
            die $dbcm->errstr if $dbcm->err;

            # fix the pictures on this comment
            my $mapid = $dbcm->selectrow_array(
                'SELECT value FROM talkprop2 '
                    . 'WHERE journalid = ? AND jtalkid = ? AND tpropid = ?',
                undef, $jid, $jtalkid, $p_id
            );
            die $dbcm->errstr if $dbcm->err;

            # but only if it exists... and it should always be 1+ due to how we use
            # the usercounters
            if ( defined $mapid && $mapid > 0 ) {
                my $kw = $fu->get_keyword_from_mapid($mapid)
                    || $u->get_keyword_from_mapid($mapid);
                if ($kw) {
                    my $newid = $tu->get_mapid_from_keyword( $kw, create => 1 );
                    die "Failed to allocate new picture_mapid.\n"
                        unless defined $newid && $newid > 0;

                    $dbcm->do(
                        'UPDATE talkprop2 SET value = ? '
                            . 'WHERE journalid = ? AND jtalkid = ? AND tpropid = ?',
                        undef, $newid, $jid, $jtalkid, $p_id
                    );
                    die $dbcm->errstr if $dbcm->err;
                }
            }

            # now nuke the memcache
            LJ::MemCache::delete( [ $jid, "talk2:$jid:$nodetype:$nodeid" ] );
            LJ::MemCache::delete( [ $jid, "talk2row:$jid:$jtalkid" ] );
            LJ::MemCache::delete( [ $jid, "talkprop:$jid:$jtalkid" ] );
        }
    }
}

sub fix_talkleft {
    my ( $fu, $tu ) = @_;

    # Expunged users have clusterid 0 and no cluster database.
    if ( $tu->clusterid ) {

        # Update global talkleft_xfp before clustered talkleft so clean_caches
        # cannot drain a row back to the old user's cluster in between.
        my $dbh = LJ::get_db_writer()
            or die "Temporary failure connecting to global master.\n";

        while (1) {
            my $rv = $dbh->do(
                'UPDATE talkleft_xfp SET userid = ? WHERE userid = ? ORDER BY posttime LIMIT 100',
                undef, $tu->id, $fu->id );
            die $dbh->errstr if $dbh->err;
            last unless $rv && $rv > 0;
        }

        if ( $fu->clusterid ) {
            my $from_dbcm = LJ::get_cluster_master($fu)
                or die "Temporary failure connecting to cluster " . $fu->clusterid . ".\n";

            my $total =
                $from_dbcm->selectrow_array( 'SELECT COUNT(*) FROM talkleft WHERE userid = ?',
                undef, $fu->id );
            die $from_dbcm->errstr if $from_dbcm->err;

            if ( $total > 0 ) {
                title( $fu, $tu, 'talkleft', 0, $total );

                if ( $fu->clusterid == $tu->clusterid ) {
                    my $ct = 0;
                    while (1) {
                        my $rv = $from_dbcm->do(
                            'UPDATE talkleft SET userid = ? '
                                . 'WHERE userid = ? ORDER BY posttime LIMIT 100',
                            undef, $tu->id, $fu->id
                        );
                        die $from_dbcm->errstr if $from_dbcm->err;
                        last unless $rv && $rv > 0;

                        $ct += $rv;
                        title( $fu, $tu, 'talkleft', $ct, $total );
                    }
                }
                else {
                    my $to_dbcm = LJ::get_cluster_master($tu)
                        or die "Temporary failure connecting to cluster " . $tu->clusterid . ".\n";

                    my $ct = 0;
                    while (1) {
                        my $rows = $from_dbcm->selectall_arrayref(
                            'SELECT posttime, journalid, nodetype, nodeid, jtalkid, publicitem '
                                . 'FROM talkleft WHERE userid = ? ORDER BY posttime LIMIT 100',
                            undef, $fu->id
                        );
                        die $from_dbcm->errstr if $from_dbcm->err;
                        last unless $rows && @$rows;

                        foreach my $row (@$rows) {
                            my ( $posttime, $journalid, $nodetype, $nodeid, $jtalkid, $publicitem )
                                = @$row;

                            $ct++;
                            title( $fu, $tu, 'talkleft', $ct, $total );

                            # Avoid duplicating a row if a previous attempt crashed after
                            # inserting on the target cluster and before deleting from the source.
                            my $exists = $to_dbcm->selectrow_array(
                                'SELECT 1 FROM talkleft '
                                    . 'WHERE userid = ? AND posttime = ? AND journalid = ? '
                                    . 'AND nodetype = ? AND nodeid = ? AND jtalkid = ? LIMIT 1',
                                undef,
                                $tu->id,
                                $posttime,
                                $journalid,
                                $nodetype,
                                $nodeid,
                                $jtalkid
                            );
                            die $to_dbcm->errstr if $to_dbcm->err;

                            unless ($exists) {
                                $to_dbcm->do(
                                    'INSERT INTO talkleft '
                                        . '(userid, posttime, journalid, nodetype, '
                                        . 'nodeid, jtalkid, publicitem) '
                                        . 'VALUES (?, ?, ?, ?, ?, ?, ?)',
                                    undef,
                                    $tu->id,
                                    $posttime,
                                    $journalid,
                                    $nodetype,
                                    $nodeid,
                                    $jtalkid,
                                    "$publicitem"
                                );
                                die $to_dbcm->errstr if $to_dbcm->err;
                            }

                            $from_dbcm->do(
                                'DELETE FROM talkleft '
                                    . 'WHERE userid = ? AND posttime = ? AND journalid = ? '
                                    . 'AND nodetype = ? AND nodeid = ? AND jtalkid = ? LIMIT 1',
                                undef,
                                $fu->id,
                                $posttime,
                                $journalid,
                                $nodetype,
                                $nodeid,
                                $jtalkid
                            );
                            die $from_dbcm->errstr if $from_dbcm->err;
                        }
                    }
                }
            }
        }
    }

    # fix the "comments posted" entry on the profile
    LJ::MemCache::delete( [ $fu->id, "talkleftct:" . $fu->id ] );
    LJ::MemCache::delete( [ $tu->id, "talkleftct:" . $tu->id ] );
}

sub title {
    my ( $fu, $tu, $which, $cur, $total ) = @_;
    my $title = sprintf( 'change-poster-id [%s :: %s -> %s :: %d/%d :: %0.2f%%]',
        $which, $fu->display_name, $tu->display_name, $cur, $total, $cur / $total * 100 );
    $0 = $title;
}

1;
