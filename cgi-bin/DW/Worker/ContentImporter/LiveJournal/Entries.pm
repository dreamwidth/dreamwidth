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
use DW::Worker::ContentImporter::Local::Entries;

sub work {
    my ( $class, $job ) = @_;

    eval { try_work( $class, $job ); };
    if ( $@ ) {
        warn "Failure running job: $@\n";
        return $class->temp_fail( $job, 'Failure running job: %s', $@ );
    }
}

sub try_work {
    my ( $class, $job ) = @_;
    my $opts = $job->arg;
    my $data = $class->import_data( $opts->{userid}, $opts->{import_data_id} );

    # failure wrappers for convenience
    my $fail      = sub { return $class->fail( $data, 'lj_entries', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_entries', $job ); };
    my $temp_fail = sub { return $class->temp_fail( $job, @_ ); };

    # setup
    my $u = LJ::load_userid( $data->{userid} )
        or return $fail->( 'Unable to load target with id %d.', $data->{userid} );
    my $entry_map = DW::Worker::ContentImporter::Local::Entries->get_entry_map( $u );

    # load the syncitems list; but never try to load the same lastsync time twice, just
    # in case 
    my ( $lastsync, %tried_syncs, %sync );
    while ( $tried_syncs{$lastsync} < 2 ) {
        warn "[$$] Attempting lastsync = " . ( $lastsync || 'undef' ) . "\n";
        my $hash = $class->call_xmlrpc( $data, 'syncitems', { lastsync => $lastsync } );

        foreach my $item ( @{$hash->{syncitems} || []} ) {
            next unless $item->{item} =~ /^L-(\d+)$/;
            $sync{$1} = [ $item->{action}, $item->{time} ];
            $lastsync = $item->{time}
                if !defined $lastsync || $item->{time} gt $lastsync;
            $tried_syncs{$lastsync}++;
        }

        warn "     count $hash->{count} == total $hash->{total}\n";
        last if $hash->{count} == $hash->{total};
    }

    my $realtime = sub {
        my $id = shift;
        return $sync{$id}->[1] if @{$sync{$id} || []};
    };

    # now get the actual events
    while ( scalar( keys %sync ) > 0 ) {
        my $count = 0;

        # calculate what time to get entries for
        my @keys = sort { $sync{$a}->[1] cmp $sync{$b}->[1] } keys %sync;
        my $lastgrab = LJ::mysql_time( LJ::mysqldate_to_time( $sync{$keys[0]}->[1] ) - 1 );

        warn "[$$] Fetching from lastsync = $lastgrab forward\n";
        my $hash = $class->call_xmlrpc( $data, 'getevents',
            {
                ver         => 1,
                lastsync    => $lastgrab,
                selecttype  => 'syncitems',
                lineendings => 'unix',
            }
        );

        foreach my $evt ( @{$hash->{events} || []} ) {
            $count++;

            $evt->{realtime} = $realtime->( $evt->{itemid} );
            $evt->{key} = $evt->{url};

            # skip this if we've already dealt with it before
            warn "     [$evt->{itemid}] $evt->{url} // $evt->{realtime} // map=$entry_map->{$evt->{key}}\n";
            my $sync = delete $sync{$evt->{itemid}};
            next if $entry_map->{$evt->{key}} || !defined $sync;

            # clean up event for LJ
            my @item_errors;

            # remap friend groups
            my $allowmask = $evt->{allowmask};
            my $newmask = $class->remap_groupmask( $data, $allowmask );

            # if we are unable to determine a good groupmask, then fall back to making
            # the entry private and mark the error.
            if ( $allowmask != 1 && $newmask == 1 ) { 
                $newmask = 0;
                push @item_errors, "Could not determine groups.";
            }

            $evt->{allowmask} = $newmask;

            my $event = $evt->{event};

            if ( $event =~ m/<.+?-poll-.+?>/ ) {
                $event =~ s/<.+?-poll-.+?>//g;

                push @item_errors, "Entry contained a poll, please manually re-add the poll.";
            }

            if ( $event =~ m/<.+?-embed-.+?>/ ) {
                $event =~ s/<.+?-embed-.+?>//g;

                push @item_errors, "Entry contained an embed tag, please manually re-add the embedded content.";
            }

            if ( $event =~ m/<.+?-template-.+?>/ ) {
                $event =~ s/<.+?-template-.+?>//g;

                push @item_errors, "Entry contained a template tag, please manually re-add the templated content.";
            }

            $evt->{event} = $class->remap_lj_user( $data, $event );

            # actually post it
            my $res = DW::Worker::ContentImporter::Local::Entries->post_event( $data, $entry_map, $u, $evt, \@item_errors );

# FIXME: do something with the return code and @item_errors ... other than
# printing them to STDERR of course ...
            if ( $res ) {
                warn "     imported!\n";
            }  else {
                warn "     failed!\n";
            }
            warn "       $_\n" foreach @item_errors;
        }

        warn "     count = $count && lastgrab = $lastgrab\n";
    }

    return $ok->();
}


1;
