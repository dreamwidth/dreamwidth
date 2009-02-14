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

    # temporary failure, this code hasn't been ported yet
    return $fail->( 'oops, not ready yet' );
}

1;
__END__

### WORK GOES HERE
    $opts->{entry_map} = DW::Worker::ContentImporter->get_entry_map($u,$opts);
    my $synccount = 0;
    my $lastsync = 0;
    my %sync;
    while (1) {
        DW::Worker::ContentImporter->ratelimit_request( $opts );
        my $hash = call_xmlrpc( $opts, 'syncitems', {lastsync => $lastsync} );

        foreach my $item ( @{$hash->{syncitems} || []} ) {
            next unless $item->{item} =~ /L-(\d+)/;
            $synccount++;
            $sync{$1} = [ $item->{action}, $item->{time} ];
            $lastsync = $item->{time} if $item->{'time'} gt $lastsync;
        }

        last if $hash->{count} == $hash->{total};
    }

    my $realtime = sub {
        my $id = shift;
        return $sync{$id}->[1] if @{$sync{$id} || []};
    };

    my $lastgrab = 0;
    while (1) {
        my $count = 0;
        DW::Worker::ContentImporter->ratelimit_request( $opts );
        my $hash = call_xmlrpc( $opts, 'getevents', { selecttype => 'syncitems', lastsync => $lastgrab, ver => 1, lineendings => 'unix', });

        foreach my $evt ( @{$hash->{events} || []} ) {
            $count++;
            $evt->{realtime} = $realtime->( $evt->{itemid} );
            $lastgrab = $evt->{realtime} if $evt->{realtime} gt $lastgrab;
            $evt->{key} = $evt->{url};

            # skip this if we've already dealt with it before
            next if $opts->{entry_map}->{$evt->{key}};
            # clean up event for LJ

            my @item_errors;

            # remap friend groups
            my $allowmask = $evt->{allowmask};
            my $newmask = remap_groupmask( $opts, $allowmask );

            # Bah. Assume private. This shouldn't relaly happen, but
            # a good sanity check.
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

            $evt->{event} = remap_lj_user( $opts, $event );

            # actually post it
            DW::Worker::ContentImporter->post_event( $u, $opts, $evt, \@item_errors );
        }

        last unless $count && $lastgrab;
    }

    $opts->{no_entries} = 1;

    return $ok->();
}


1;