#!/usr/bin/perl
#
# DW::Task::ESN::FilterSubs
#
# ESN worker to do final subscription processing.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2019 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::ESN::FilterSubs;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::Stats;
use DW::TaskQueue;
use LJ::Event;
use LJ::ESN;
use LJ::Subscription;

use base 'DW::Task';

sub work {
    my $self = $_[0];
    my $a    = $self->args;

    my $failed = sub {
        $log->error( sprintf( $_[0], @_[ 1 .. $#_ ] ) );
        return DW::Task::FAILED;
    };

    my ( $e_params, $sublist, $cid ) = @$a;
    my $evt = eval { LJ::Event->new_from_raw_params(@$e_params) }
        or return $failed->("Couldn't load event: $@");

    $evt->configure_logger;

    my $us = LJ::load_userids( map { $_->[0] } @$sublist );

    # Filter out subs whose users don't live on this cluster, logging each
    # drop. Previously this was a silent grep which made it impossible to
    # tell "user moved cluster" apart from "user failed to load under DB
    # pressure" -- both being live sources of silently dropped notifications.
    my @kept;
    foreach my $item (@$sublist) {
        my $uid  = $item->[0];
        my $user = $us->{$uid};
        if ( $user && $user->{clusterid} == $cid ) {
            push @kept, $item;
            next;
        }

        my $reason = $user ? 'cluster_mismatch' : 'user_not_loaded';
        my $uname  = $user ? $user->{user}      : '?';
        my $got    = $user ? $user->{clusterid} : 'none';
        $log->info(
            sprintf(
                'ESN drop filtersubs user=%s(%d) sub=%d cluster=%d->%s reason=%s',
                $uname, $uid, $item->[1], $cid, $got, $reason
            )
        );
        DW::Stats::increment( 'dw.esn.filtersubs.dropped', 1,
            [ "etypeid:$e_params->[0]", "cluster:$cid", "reason:$reason" ] );
    }
    $sublist = \@kept;

    my ( $ct, $max ) = ( 0, scalar(@$sublist) );
    my $dbcr = LJ::get_cluster_reader($cid)
        or return $failed->("Couldn't get cluster reader handle");

    $log->debug( 'Filtering: got ', $max, ' subs to filter.' );

    my @subs;
    while ( scalar(@$sublist) > 0 ) {
        my @slice = splice( @$sublist, 0, 100 );
        $ct += scalar(@slice);
        $0 = sprintf( 'esn-filter-subs [%d/%d] %0.2f%', $ct, $max, ( $ct / $max * 100 ) );

        my $qry = q{SELECT userid, subid, is_dirty, journalid, etypeid,
                    arg1, arg2, ntypeid, createtime, expiretime, flags 
                    FROM subs WHERE };
        $qry .= join( ' OR ', map { "(userid = ? AND subid = ?)" } @slice );

        my $res =
            $dbcr->selectall_hashref( $qry, [ 'userid', 'subid' ], undef, map { @$_ } @slice );
        return $failed->( $dbcr->errstr ) if $dbcr->err;

        # We have to do it like this so we get hashes back. Else, we have to
        # build them ourselves. This is easier.
        foreach my $hr ( values %$res ) {
            foreach my $row ( values %$hr ) {
                my $sub = LJ::Subscription->new_from_row($row)
                    or next;
                push @subs, $sub;
            }
        }
    }

    $0 = 'esn-filter-subs [bored]';

    DW::TaskQueue->send( LJ::ESN->tasks_of_unique_matching_subs( $evt, @subs ) );
    return DW::Task::COMPLETED;
}

1;

