#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal::Entries
#
# Importer worker for LiveJournal-based sites entries.
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

package DW::Worker::ContentImporter::LiveJournal::Entries;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

use Carp qw/ croak confess /;
use Time::HiRes qw/ tv_interval gettimeofday /;
use DW::Worker::ContentImporter::Local::Entries;

sub work {

    # VITALLY IMPORTANT THAT THIS IS CLEARED BETWEEN JOBS
    %DW::Worker::ContentImporter::LiveJournal::MAPS = ();

    my ( $class, $job ) = @_;
    my $opts = $job->arg;
    my $data = $class->import_data( $opts->{userid}, $opts->{import_data_id} );

    eval { try_work( $class, $job, $opts, $data ); };
    if ( my $msg = $@ ) {
        $msg =~ s/\r?\n/ /gs;
        return $class->temp_fail( $data, 'lj_entries', $job, 'Failure running job: %s', $msg );
    }

    # FIXME: temporary hack to reclaim memory when we have imported entries
    exit 0;
}

sub try_work {
    my ( $class, $job, $opts, $data ) = @_;
    my $begin_time = [ gettimeofday() ];

    # we know that we can potentially take a while, so budget an hour for
    # the import job before someone else comes in to snag it
    $job->grabbed_until( time() + 3600 );
    $job->save;

    # failure wrappers for convenience
    my $fail      = sub { return $class->fail( $data, 'lj_entries', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_entries', $job ); };
    my $temp_fail = sub { return $class->temp_fail( $data, 'lj_entries', $job, @_ ); };
    my $status    = sub { return $class->status( $data, 'lj_entries', { @_ } ); };

    # logging sub
    my ( $logfile, $last_log_time );
    my $log = sub {
        $last_log_time ||= [ gettimeofday() ];

        unless ( $logfile ) {
            mkdir "$LJ::HOME/logs/imports";
            mkdir "$LJ::HOME/logs/imports/$opts->{userid}";
            open $logfile, ">>$LJ::HOME/logs/imports/$opts->{userid}/$opts->{import_data_id}.lj_entries.$$"
                or return $temp_fail->( 'Internal server error creating log.' );
            print $logfile "[0.00s 0.00s] Log started at " . LJ::mysql_time(gmtime()) . ".\n";
        }

        my $fmt = "[%0.4fs %0.1fs] " . shift() . "\n";
        my $msg = sprintf( $fmt, tv_interval( $last_log_time ), tv_interval( $begin_time), @_ );

        print $logfile $msg;
        $job->debug( $msg );

        $last_log_time = [ gettimeofday() ];
    };

    # setup
    my $u = LJ::load_userid( $data->{userid} )
        or return $fail->( 'Unable to load target with id %d.', $data->{userid} );
    $log->( 'Import begun for %s(%d).', $u->user, $u->userid );

    # title munging
    my $title = sub {
        my $msg = sprintf( shift(), @_ );
        $msg = " $msg" if $msg;

        $0 = sprintf( 'content-importer [entries: %s(%d)%s]', $u->user, $u->id, $msg );
    };
    $title->();

    # load entry map
    my $entry_map = DW::Worker::ContentImporter::Local::Entries->get_entry_map( $u ) || {};
    $log->( 'Loaded entry map with %d entries.', scalar( keys %$entry_map ) );

    # and xpost map
    my $xpost_map = $class->get_xpost_map( $u, $data ) || {};
    $log->( 'Loaded xpost map with %d entries.', scalar( keys %$xpost_map ) );

    # this is a helper sub that steps a MySQL formatted time by some offset
    # arguments: '2008-01-01 12:03:53', -1 ... returns '2008-01-01 12:03:52'
    my $step_time = sub {
        return LJ::mysql_time( LJ::mysqldate_to_time( $_[0] ) + $_[1] );
    };

    # load the syncitems list; but never try to load the same lastsync time twice, just
    # in case.  also, we have to do some pretty annoying back-steps and not actually trust
    # the last synced time because it's possible in some rare cases to lose entries by
    # just trusting what the remote end is telling you.  (FIXME: link to a writeup of this
    # somewhere...)
    my ( $lastsync, %tried_syncs, %sync );
    while ( $tried_syncs{$lastsync} < 2 ) {
        $log->( 'Calling syncitems; lastsync = %s.', ( $lastsync || 'undef' ) );
        my $hash = $class->call_xmlrpc( $data, 'syncitems', { lastsync => $lastsync } );
        return $temp_fail->( 'XMLRPC failure: ' . $hash->{faultString} )
            if ! $hash || $hash->{fault};

        foreach my $item ( @{$hash->{syncitems} || []} ) {
            # ensure we always step the sync time forward
            my $synctime = $step_time->( $item->{time}, -1 );
            $lastsync = $synctime
                if !defined $lastsync || $synctime gt $lastsync;

            # but only store it in %sync if it's an entry
            $sync{$1} = [ $item->{action}, $synctime ]
                if $item->{item} =~ /^L-(\d+)$/;
        }

        # now we can mark this, as we have officially syncd this time
        $tried_syncs{$lastsync}++;

        $title->( 'syncitems - %d left', $hash->{title} );
        $log->( '    retrieved %d items and %d left to sync', $hash->{count}, $hash->{total} );
        last if $hash->{count} == $hash->{total};
    }
    $log->( 'Syncitems finished with %d items pre-prune.', scalar( keys %sync ) );

    # this is an optimization.  since we never do an edit event (only post!) we will
    # never get changes anyway.  so let's remove from the list of things to sync any
    # post that we already know about.  (not that we really care, but it's much nicer
    # on people we're pulling from.)
    foreach my $url ( keys %$entry_map ) {

        # but first, let's skip anything that isn't from the server we are importing
        # from.  this assumes URLs never have other hostnames, so if someone were to
        # register testlivejournal.com and do an import, they will have trouble
        # importing.  if they want to do that to befunge this logic, more power to them.
        $url =~ s/-/_/g; # makes \b work below
        next unless $url =~ /\Q$data->{hostname}\E/ &&
                    $url =~ /\b$data->{username}\b/;

        unless ( $url =~ m!/(\d+)\.html$! ) {
            $log->( 'URL %s not of expected format in prune.', $url );
            next;
        }

        # FIXME: this is the key moment to "skip".  if we want a paid user or someone
        # to get their picture keyword updated, we should skip them here.
        # FIXME: this is a fixme because we should implement some way of making
        # this available to users.
        delete $sync{$1 >> 8};
    }
    $log->( 'Syncitems now has %d items post-prune (first pass).', scalar( keys %sync ) );

    # this is another optimization.  we know crossposted entries can be removed from
    # the list of things we will import, as we generated them to begin with.
    foreach my $itemid ( keys %$xpost_map ) {
        delete $sync{$itemid};
    }
    $log->( 'Syncitems now has %d items post-prune (second pass).', scalar( keys %sync ) );

    $title->( 'post-prune' );

    # simple helper sub
    my $realtime = sub {
        my $id = shift;
        return $sync{$id}->[1] if @{$sync{$id} || []};
    };

    # helper so we don't have to get so much FOAF data
    my %user_map;

    # now get the actual events
    while ( scalar( keys %sync ) > 0 ) {
        my ( $count, $last_itemid ) = ( 0, undef );

        # this is a useful helper sub we use in both import modes: lastsync and one
        my $process_entry = sub {
            my $evt = shift;

            $count++;

            $evt->{realtime} = $realtime->( $evt->{itemid} );
            $evt->{key} = $evt->{url};

            # skip this if we've already dealt with it before
            $log->( '    %d %s %s; mapped = %d (import_source) || %d (xpost).',
                    $evt->{itemid}, $evt->{url}, $evt->{realtime}, $entry_map->{$evt->{key}},
                    $xpost_map->{$evt->{itemid}} );

            # always set the picture_keyword property though, in case they're a paid
            # user come back to fix their keywords.  this forcefully overwrites their
            # local picture keyword
            if ( my $jitemid = $entry_map->{$evt->{key}} ) {
                my $entry = LJ::Entry->new( $u, jitemid => $jitemid );
                $entry->set_prop( picture_keyword => $evt->{props}->{picture_keyword} );
            }

            # now try to skip it
            my $sync = delete $sync{$evt->{itemid}};
            return if $entry_map->{$evt->{key}} || !defined $sync || $xpost_map->{$evt->{itemid}};

            # clean up event for LJ
            my @item_errors;

            # remap friend groups
            my $allowmask = $evt->{allowmask};
            my $newmask = $class->remap_groupmask( $data, $allowmask );

            # if we are unable to determine a good groupmask, then fall back to making
            # the entry private and mark the error.
            if ( $allowmask != 1 && $newmask == 1 ) {
                $newmask = 0;
                push @item_errors, "Could not determine groups to post to.";
            }
            $evt->{allowmask} = $newmask;

            # now try to determine if we need to post this as a user
            my $posteru;
            if ( $evt->{poster} && $evt->{poster} ne $data->{username} ) {
                my $posterid = exists $user_map{$evt->{poster}} ? $user_map{$evt->{poster}} :
                    DW::Worker::ContentImporter::LiveJournal->remap_username_friend( $data, $evt->{poster} );

                unless ( $posterid ) {
                    # set it to 0, but exists, so we don't hit LJ again, but we continue to fail this poster
                    $user_map{$evt->{poster}} = 0;

                    # FIXME: need a better way of totally dying...
                    push @item_errors, "Unable to map poster from LJ user '$evt->{poster}' to local user.";
                    $status->(
                        remote_url => $evt->{url},
                        errors     => \@item_errors,
                    );
                    return;
                }

                $user_map{$evt->{poster}} ||= $posterid;
                $posteru = LJ::load_userid( $posterid );
            }

            # we just link polls to the original site
# FIXME: this URL should be from some method and not manually constructed
            my $event = $evt->{event};
            $event =~ s!<.+?-poll-(\d+?)>![<a href="http://www.$data->{hostname}/poll/?id=$1">Poll #$1</a>]!g;

            if ( $event =~ m/<.+?-embed-.+?>/ ) {
                $event =~ s/<.+?-embed-.+?>//g;

                push @item_errors, "Entry contained an embed tag, please manually re-add the embedded content.";
            }

            if ( $event =~ m/<.+?-template-.+?>/ ) {
                $event =~ s/<.+?-template-.+?>//g;

                push @item_errors, "Entry contained a template tag, please manually re-add the templated content.";
            }

            $evt->{event} = $class->remap_lj_user( $data, $event );
            $evt->{subject} = $class->remap_lj_user( $data, $evt->{subject} || "" );

            # actually post it
            my ( $ok, $res ) =
                DW::Worker::ContentImporter::Local::Entries->post_event( $data, $entry_map, $u, $posteru, $evt, \@item_errors );

            # now record any errors that happened
            $status->(
                remote_url => $evt->{url},
                post_res   => $res,
                errors     => \@item_errors,
            ) if @item_errors;

        };

        # calculate what time to get entries for
        my ( $tries, $lastgrab, $hash ) = ( 0, undef, undef );
SYNC:   while ( $tries++ <= 10 ) {

            # if we ever get in here with no entries left, we're done.  this sometimes happens
            # when the manual advance import code hits the end of the sidewalk and runs out of
            # things to import.
            last unless keys %sync;

            # calculate the oldest entry we haven't retrieved yet, and offset that time by
            # $tries, so we can break the 'broken client' logic (note: we assert that we are
            # not broken.)
            my @keys = sort { $sync{$a}->[1] cmp $sync{$b}->[1] } keys %sync;
            $last_itemid = $keys[0];
            $lastgrab = $step_time->( $sync{$last_itemid}->[1], -$tries );

            $title->( 'getevents - lastsync %s', $lastgrab );
            $log->( 'Loading entries; lastsync = %s, itemid = %d.', $lastgrab, $keys[0] );
            $hash = $class->call_xmlrpc( $data, 'getevents',
                {
                    ver         => 1,
                    lastsync    => $lastgrab,
                    selecttype  => 'syncitems',
                    lineendings => 'unix',
                }
            );

            # sometimes LJ doesn't like us on large imports or imports where the user has
            # used the mass privacy tool in the past.  so, if we run into the 'you are broken'
            # error, let's grab some older entries.  the goal here is mainly to advance
            # the clock by at least 10 seconds.  this means we may end up downloading only
            # one or two entries manually, but in some cases it means we may end up doing
            # hundreds of entries.  depends on what kind of state the user is in.
            if ( $hash && $hash->{fault} && $hash->{faultString} =~ /broken/ ) {
                $log->( '    repeated requests error, falling back to manual advance.' );

                # figure out which items we should try to get, based on the logic that we
                # should get at least 10 seconds or 20 items, whichever is more.  the former
                # for the case where mass privacy breaks us, the latter for the case where
                # the Howard Predicament* bites us.
                #
                # * the Howard Predicament has only been observed in the wild once.  the
                #   noted behavior is that, no matter what lastsync value we send, the
                #   remote server chooses to tell us we're broken.  this should not be
                #   possible, but it happened to my friend Howard, and I couldn't solve
                #   it through any other means than bypassing lastsync.  sigh.
                #

                my $stop_after = $step_time->( $lastgrab, $tries + 10 );
                $log->( 'Manual advance will stop at %s or 20 entries, whichever is more.', $stop_after );

                my @keys = sort { $sync{$a}->[1] cmp $sync{$b}->[1] } keys %sync;
                pop @keys
                    while scalar( @keys ) > 20 && $sync{$keys[-1]}->[1] gt $stop_after;

                $log->( 'Found %d entries to grab manually.', scalar( @keys ) );

                # now get them, one at a time
                my @events;
                foreach my $itemid ( @keys ) {
                    $log->( 'Fetching itemid %d.', $itemid );

                    # try to get it from the remote server
                    $hash = $class->call_xmlrpc( $data, 'getevents',
                        {
                            ver         => 1,
                            itemid      => $itemid,
                            selecttype  => 'one',
                            lineendings => 'unix',
                        }
                    );

                    # if we get an error, then we have to abort the import
                    return $temp_fail->( 'XMLRPC failure: ' . $hash->{faultString} )
                        if ! $hash || $hash->{fault};

                    # another observed oddity: sometimes the remote server swears that
                    # an entry exists, but we can't get it.  even asking for it by name.
                    # if there was no error, and no entry returned, skip it.
                    if ( scalar( @{ $hash->{events} || [] } ) == 0 ) {
                        $log->( 'Itemid %d seems to be a phantom.', $itemid );
                        delete $sync{$itemid};
                        next;
                    }

                    # good, import this event
                    $process_entry->( $_ )
                        foreach @{ $hash->{events} || [] };
                }

                next SYNC;
            }

            # bail if we get a different error
            return $temp_fail->( 'XMLRPC failure: ' . $hash->{faultString} )
                if ! $hash || $hash->{fault};

            # if we get here we're probably in good shape, bail out
            last;
        }

        # there is a slight chance we will get here if we run out of 'broken' retries
        # so check for that
        return $temp_fail->( 'XMLRPC failure: ' . $hash->{faultString} )
            if ! $hash || $hash->{fault};

        # iterate over events and import them
        $process_entry->( $_ )
            foreach @{$hash->{events} || []};

        # if we get here, we got a good result, which means that the entry we tried to get
        # should be in the results.  if it's not, to prevent an infinite loop, let's mark
        # it as retrieved.  FIXME: this causes problems with mass-edited journals
        delete $sync{$last_itemid} if defined $last_itemid;

        # log some status for later
        $log->( '    counted %d entries, lastgrab is now %s.', $count, $lastgrab );
    }

    # mark the comments mode as ready to schedule
    my $dbh = LJ::get_db_writer();
    $dbh->do(
        q{UPDATE import_items SET status = 'ready'
          WHERE userid = ? AND item IN ('lj_comments')
          AND import_data_id = ? AND status = 'init'},
        undef, $u->id, $opts->{import_data_id}
    );

    return $ok->();
}


1;
