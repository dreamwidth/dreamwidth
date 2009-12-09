#!/usr/bin/perl
#
# DW::Worker::UserpicRenameWorker
#
# TheSchwartz worker module for renaming userpics.  Called with
# LJ::theschwartz()->insert('DW::Worker::UserpicRenameWorker', { 
# 'uid' => $u->userid, 'keywordmap' => Storable::nfreeze(\%keywordmap);
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

package DW::Worker::UserpicRenameWorker;

use strict;
use warnings;
use base 'TheSchwartz::Worker';

sub schwartz_capabilities { return ('DW::Worker::UserpicRenameWorker'); }

sub keep_exit_status_for { 86400 } # 24 hours

my $logpropid;
my $talkpropid;

sub work {
    my ($class, $job) = @_;

    my $arg = $job->arg;

    my ($uid, $keywordmapstring) = map { delete $arg->{$_} } qw( uid keywordmap );

    return $job->permanent_failure("Unknown keys: " . join(", ", keys %$arg))
        if keys %$arg;
    return $job->permanent_failure("Missing argument")
        unless defined $uid && defined $keywordmapstring;

    my $keywordmap = eval { Storable::thaw($keywordmapstring) } or return $job->failed("Failed to load keywordmap from arg '$keywordmapstring':  " . $@);

    # get the user from the uid
    my $u = LJ::want_user($uid) or return $job->failed("Unable to load user with uid $uid");

    # only get the propids once; they're not going to change
    unless ($logpropid && $talkpropid) {
        $logpropid = LJ::get_prop( log => 'picture_keyword' )->{id};
        $talkpropid = LJ::get_prop( talk => 'picture_keyword' )->{id};
    }

    # only update 1000 rows at a time.
    my $LIMIT = 1000;

    # now we go through each cluster and update the logprop2 and talkprop2
    # tables with the new values.
    foreach my $cluster_id (@LJ::CLUSTERS) {
        my $dbcm = LJ::get_cluster_master($cluster_id);
        
        foreach my $kw (keys %$keywordmap) {
            # find entries for clearing cache
            my $matches = $dbcm->selectall_arrayref(q{
                SELECT log2.journalid AS journalid, 
                       log2.jitemid AS jitemid 
                FROM logprop2 
                INNER JOIN log2 
                    ON ( logprop2.journalid = log2.journalid 
                        AND logprop2.jitemid = log2.jitemid ) 
                WHERE posterid = ? 
                    AND propid=?
                    AND value = ?
                }, undef, $u->id, $logpropid, $kw);

            # update entries
            my $updateresults = $LIMIT;
            while ($updateresults == $LIMIT) {
                $updateresults = $dbcm->do( q{
                    UPDATE logprop2 
                    SET value = ? 
                    WHERE propid=? 
                        AND value = ? 
                        AND EXISTS ( 
                            SELECT posterid 
                            FROM log2 
                            WHERE log2.journalid = logprop2.journalid 
                                AND log2.jitemid = logprop2.jitemid 
                                AND log2.posterid = ? )
                    LIMIT ?
                    }, undef, $keywordmap->{$kw}, $logpropid, $kw, $u->id, $LIMIT);
                return $job->permanent_failure($dbcm->errstr) if $dbcm->err;
            }

            # clear cache
            foreach my $match (@$matches) {
                LJ::MemCache::delete([ $match->[0], "logprop:" . $match->[0]. ":" . $match->[1] ]);
            }
            
            # update comments
            # find comments for clearing cache
            $matches = $dbcm->selectall_arrayref( q{
                SELECT talkprop2.journalid AS journalid, 
                       talkprop2.jtalkid AS jtalkid 
                FROM talkprop2 
                INNER JOIN talk2 
                    ON ( talkprop2.journalid = talk2.journalid 
                        AND talkprop2.jtalkid = talk2.jtalkid ) 
                WHERE posterid = ? 
                    AND tpropid=? 
                    AND value = ? 
                }, undef, $u->id, $talkpropid, $kw);
            
            # update coments
            $updateresults = $LIMIT;
            while ($updateresults == $LIMIT) {
                $updateresults = $dbcm->do( q{
                    UPDATE talkprop2 
                    SET value = ? 
                    WHERE tpropid=? 
                        AND value = ? 
                        AND EXISTS ( 
                            SELECT posterid 
                            FROM talk2 
                            WHERE talk2.journalid = talkprop2.journalid 
                                AND talk2.jtalkid = talkprop2.jtalkid 
                                AND talk2.posterid = ? ) 
                    LIMIT ? 
                    }, undef, $keywordmap->{$kw}, $talkpropid, $kw, $u->id, $LIMIT);
                return $job->permanent_failure($dbcm->errstr) if $dbcm->err;
            }

            # clear cache
            foreach my $match (@$matches) {
                LJ::MemCache::delete([ $match->[0], "talkprop:" . $match->[0]. ":" . $match->[1] ]);
            }
        }
    }

    $job->completed;
}

1;
