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
# Copyright (c) 2009-2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::ContentImporter::LiveJournal::Entries;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

use DW::Importer::Source::LiveJournal::Keys qw( index_entries );
use DW::Importer::Transform::LJMarkup qw( remap_user_tags entry_text );
use DW::Importer::Transform::Security qw( map_security );

# importing entries leaks memory, so the worker process exits afterwards to reclaim it
sub exit_after_job { 1 }

sub run {
    my ( $class,  $ctx )  = @_;
    my ( $data,   $job )  = ( $ctx->data, $ctx->job );
    my ( $source, $sink ) = ( $class->source_for($ctx), $ctx->sink );

    # we know that we can potentially take a while, so budget some hours for
    # the import job before someone else comes in to snag it
    $job->grabbed_until( time() + 3600 * 12 );
    $job->save;

    my $log   = sub { return $ctx->log(@_); };
    my $title = sub { return $ctx->title(@_); };

    # load entry map
    my $entry_map = $sink->entry_map;
    $log->( 'Loaded entry map with %d entries.', scalar( keys %$entry_map ) );

    # and xpost map
    my $xpost_map = $sink->xpost_map( $data->{hostname}, $data->{username} ) || {};
    $log->( 'Loaded xpost map with %d entries.', scalar( keys %$xpost_map ) );

    # get the itemid of the most recent entry (just so we know how many entries there have
    # been in the life of this account)
    my ( $maxid, $fetched ) = $source->newest_entry_id($log);

    # we got entries but weren't able to find a single *non*-DOOO entry.
    # No idea what the actual latest entry is. Give up now, tell the user to fix it
    unless ($maxid) {
        $log->( 'Got %d entries but all were DOOO.', $fetched );
        return $ctx->fail(
"We weren't able to find your latest entry because you have several entries that are dated out of order (DOOO, or backdated). "
                . "Please edit all the entries on %s that are DOOO and set their date to one that's earlier than your latest non-DOOO entry. "
                . "Then try your import again.",
            $data->{hostname}
        );
    }

    my %has = $class->find_prunable_items(
        $entry_map, $xpost_map,
        hostname       => $data->{hostname},
        username       => $data->{username},
        log_sub        => $log,
        force_reimport => $data->{options}->{lj_entries_remap_icon}
    );
    $sink->note(
        skip   => type => 'entry',
        count  => scalar( keys %has ),
        reason => 'already imported, so not fetched again'
    ) if %has;
    $title->('post-prune');

    delete @{ $ctx->cache }{qw( fg_map fg_state )};
    my ( $groupmap, $group_revision ) = $class->groupmap_state($ctx);

    # this is a useful helper sub we use
    my $process_entry = sub {
        my $evt = $_[0];

        $log->(
            '    %d %s %s; mapped = %d (import_source) || %d (xpost).',
            $evt->{itemid}, $evt->{url}, $evt->{logtime},
            $entry_map->{ $evt->{key} },
            $xpost_map->{ $evt->{itemid} }
        );

        # always set the picture_keyword property though, in case they're a paid
        # user come back to fix their keywords.  this forcefully overwrites their
        # local picture keyword
        if ( my $jitemid = $entry_map->{ $evt->{key} } ) {
            $sink->update_entry_icon( $jitemid, $evt->{props}->{picture_keyword} );
        }

        # now try to skip it if we already have it
        if (   $entry_map->{ $evt->{key} }
            || $xpost_map->{ $evt->{itemid} }
            || $has{ $evt->{itemid} } )
        {
            $sink->note(
                skip   => type => 'entry',
                target => $evt->{key},
                reason => $xpost_map->{ $evt->{itemid} }
                ? 'crossposted from here'
                : 'already imported'
            );
            return;
        }

        $evt->{subject} = remap_user_tags( $evt->{subject} || "", $data->{hostname} );

        # work out who can read it here. if we are unable to determine a good groupmask,
        # this makes the entry private and says so.
        my @item_errors;
        my $security = map_security(
            security  => $evt->{security},
            allowmask => $evt->{allowmask},
            groupmap  => $groupmap
        );
        $evt->{security}  = $security->{security};
        $evt->{allowmask} = $security->{allowmask};
        push @item_errors, @{ $security->{warnings} };

        # now try to determine if we need to post this as a user
        my $posterid;
        if ( $data->{usejournal} ) {
            my $fid;
            ( $posterid, $fid ) = $class->get_remapped_userids( $ctx, $evt->{poster}, $log );

            unless ($posterid) {

                # FIXME: need a better way of totally dying...
                push @item_errors,
                    "Unable to map poster from LJ user '$evt->{poster}' to local user.";
                $ctx->status(
                    remote_url => $evt->{url},
                    errors     => \@item_errors,
                );
                return;
            }
        }

        # polls, embeds and templates, and the user tags
        my ( $event, @markup_warnings ) = entry_text( $evt->{event}, $data->{hostname} );
        push @item_errors, @markup_warnings;
        $evt->{event} = $event;

        # actually post it
        my ( $ok, $res ) = $sink->post_entry(
            $evt,
            posterid => $posterid,
            errors   => \@item_errors,
            (
                $evt->{security} eq 'usemask' && ( $evt->{allowmask} & ~1 )
                ? ( group_revision => $group_revision )
                : ()
            ),
        );
        $sink->note( warning => target => $evt->{key}, text => $_ ) foreach @item_errors;

        # we don't need this text anymore, so nuke it to try to save memory
        delete $evt->{event};
        delete $evt->{subject};

        # now record any errors that happened
        $ctx->status(
            remote_url => $evt->{url},
            post_res   => $res,
            errors     => \@item_errors,
        ) if @item_errors;

    };

    # helper to load some events -- dies with a failure outcome if errors were encountered.
    my $fetch_events = sub {

        # let them know we're still working
        $job->grabbed_until( time() + 3600 );
        $job->save;

        # clear "request" cache of db handles to force revalidation, whenever fetching a block
        # of entries, to avoid possibly using one that was idle too long without testing it.
        $LJ::DBIRole->clear_req_cache();

        $log->( 'Fetching %d items.', scalar @_ );
        $title->( 'getevents - %d to %d', $_[0], $_[-1] );

        # if we get an error, then we have to abort the import
        # good, import these entries
        $process_entry->($_) foreach $source->entries(@_);
    };

    # now get the actual events
    my @toload;
    foreach my $jid ( 0 .. $maxid ) {
        push @toload, $jid
            unless exists $has{$jid} && $has{$jid};
        if ( scalar @toload == 100 ) {
            $fetch_events->(@toload);
            @toload = ();
        }
    }
    $fetch_events->(@toload) if scalar @toload > 0;

    # Kick off a indexing job for this user
    $sink->dispatch_search_copy('importen');

    return $ctx->ok;
}

# which remote entry ids don't need fetching: the ones we already have (unless the user asked to
# update their icons, which needs them again) and the ones we crossposted there. returns a hash
# of remote itemid => 1
sub find_prunable_items {
    my ( $class, $entry_map, $xpost_map, %opts ) = @_;

    my $log = $opts{log_sub} || sub { warn @_ };

    # this is an optimization.  since we never do an edit event (only post!) we will
    # never get changes anyway.  so let's remove from the list of things to sync any
    # post that we already know about.  (not that we really care, but it's much nicer
    # on people we're pulling from.)
    my $index = index_entries( $entry_map, $opts{hostname}, $opts{username} );
    $log->( 'URL %s not of expected format in prune.', $_ ) foreach @{ $index->{unparsed} };

    # if we want a paid user or someone to get their picture keyword updated,
    # skip them here.
    my %has = $opts{force_reimport} ? () : map { $_ => 1 } keys %{ $index->{by_remote_id} };
    $log->( 'Identified %d items we already know about (first pass).', scalar( keys %has ) );

    # this is another optimization.  we know crossposted entries can be removed from
    # the list of things we will import, as we generated them to begin with.
    $has{$_} = 1 foreach keys %$xpost_map;
    $log->( 'Identified %d items we already know about (second pass).', scalar( keys %has ) );

    return %has;
}

1;
