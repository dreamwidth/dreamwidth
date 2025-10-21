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

use Carp qw/ croak confess /;
use Time::HiRes qw/ tv_interval gettimeofday /;
use DW::Worker::ContentImporter::Local::Entries;

sub work {

    # VITALLY IMPORTANT THAT THIS IS CLEARED BETWEEN JOBS
    %DW::Worker::ContentImporter::LiveJournal::MAPS = ();
    LJ::start_request();

    my ( $class, $job ) = @_;
    my $opts = $job->arg;
    my $data = $class->import_data( $opts->{userid}, $opts->{import_data_id} );

    return $class->decline($job) unless $class->enabled($data);

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

    # we know that we can potentially take a while, so budget some hours for
    # the import job before someone else comes in to snag it
    $job->grabbed_until( time() + 3600 * 12 );
    $job->save;

    # failure wrappers for convenience
    my $fail      = sub { return $class->fail( $data, 'lj_entries', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_entries', $job ); };
    my $temp_fail = sub { return $class->temp_fail( $data, 'lj_entries', $job, @_ ); };
    my $status    = sub { return $class->status( $data, 'lj_entries', {@_} ); };

    # logging sub
    my ( $logfile, $last_log_time );
    $logfile = $class->start_log(
        "lj_entries",
        userid         => $opts->{userid},
        import_data_id => $opts->{import_data_id}
    ) or return $temp_fail->('Internal server error creating log.');

    my $log = sub {
        $last_log_time ||= [ gettimeofday() ];

        my $fmt = "[%0.4fs %0.1fs] " . shift() . "\n";
        my $msg = sprintf( $fmt, tv_interval($last_log_time), tv_interval($begin_time), @_ );

        print $logfile $msg;
        $job->debug($msg);

        $last_log_time = [ gettimeofday() ];
    };

    # setup
    my $u = LJ::load_userid( $data->{userid} )
        or return $fail->( 'Unable to load target with id %d.', $data->{userid} );
    $log->( 'Import begun for %s(%d).', $u->user, $u->userid );
    $log->( 'memory usage is now %dMB', LJ::gtop()->proc_mem($$)->resident / 1024 / 1024 );

    # title munging
    my $title = sub {
        my $msg = sprintf( shift(), @_ );
        $msg = " $msg" if $msg;

        $0 = sprintf( 'content-importer [entries: %s(%d)%s]', $u->user, $u->id, $msg );
    };
    $title->();

    # load entry map
    my $entry_map = DW::Worker::ContentImporter::Local::Entries->get_entry_map($u) || {};
    $log->( 'Loaded entry map with %d entries.', scalar( keys %$entry_map ) );
    $log->( 'memory usage is now %dMB',          LJ::gtop()->proc_mem($$)->resident / 1024 / 1024 );

    # and xpost map
    my $xpost_map = $class->get_xpost_map( $u, $data ) || {};
    $log->( 'Loaded xpost map with %d entries.', scalar( keys %$xpost_map ) );
    $log->( 'memory usage is now %dMB',          LJ::gtop()->proc_mem($$)->resident / 1024 / 1024 );

    # get the itemid of the most recent entry (just so we know how many entries there have
    # been in the life of this account)
    $log->('Fetching the most recent entry.');
    my $last = $class->call_xmlrpc(
        $data,
        'getevents',
        {
            ver         => 1,
            selecttype  => 'lastn',
            howmany     => 50,
            lineendings => 'unix',
        }
    );

    my $xmlrpc_fail = 'XMLRPC failure: ' . ( $last ? $last->{faultString} : '[unknown]' );
    $xmlrpc_fail .= " (community: $data->{usejournal})" if $data->{usejournal};
    return $temp_fail->($xmlrpc_fail) if !$last || $last->{fault};

    # we weren't able to get any data. Maybe weren't able to connect to remote server?
    # we want to try again
    return $temp_fail->('Failed to fetch the most recent entry.')
        unless ref $last->{events} eq 'ARRAY';

    # look for the latest non-DOOO entry
    # first entry may be a sticky entry (can't tell via props)
    #   so we guess by taking the max non-DOOO entry on this list
    my $maxid;
    foreach my $event ( @{ $last->{events} } ) {
        if ( $event->{props}->{opt_backdated} ) {
            $log->( 'Skipping %d -- backdated', $event->{itemid} );
        }
        else {
            $maxid = $event->{itemid} > $maxid ? $event->{itemid} : $maxid;
        }
    }
    $log->( 'Discovered that the maximum jitemid on the remote is %d.', $maxid ) if $maxid;

    # we got entries but weren't able to find a single *non*-DOOO entry.
    # No idea what the actual latest entry is. Give up now, tell the user to fix it
    unless ($maxid) {
        $log->( 'Got %d entries but all were DOOO.', scalar @{ $last->{events} } );
        return $fail->(
"We weren't able to find your latest entry because you have several entries that are dated out of order (DOOO, or backdated). "
                . "Please edit all the entries on %s that are DOOO and set their date to one that's earlier than your latest non-DOOO entry. "
                . "Then try your import again.",
            $data->{hostname}
        );
    }

    my ( $duplicates_map, %has ) = $class->find_prunable_items(
        $u, $entry_map, $xpost_map,
        hostname       => $data->{hostname},
        username       => $data->{username},
        log_sub        => $log,
        force_reimport => $data->{options}->{lj_entries_remap_icon}
    );
    $title->('post-prune');

    # this is a useful helper sub we use
    my $count         = 0;
    my $process_entry = sub {
        my $evt  = $_[0];
        my $user = $data->{usejournal} // $data->{username};

        # Key for entry_map. We know the username and the site, so we set this to
        # something that is dependable.
        $evt->{key} =
            $data->{hostname} . '/' . $user . '/' . ( $evt->{itemid} * 256 + $evt->{anum} );

        # We also need to calculate the remote URL for ESN purposes.
        my $ext_u = DW::External::User->new(
            user => $user,
            site => $data->{hostname}
        );

        # Although I don't think this is likely to ever croak,
        # I'm being extra-cautious and using an eval here to
        # make sure this can't interrupt the import process.
        $evt->{url} = eval { $ext_u->site->entry_url( $ext_u, %$evt ) };

        $count++;
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
            my $entry = LJ::Entry->new( $u, jitemid => $jitemid );
            my $kw    = $evt->{props}->{picture_keyword};
            if ( $u->userpic_have_mapid ) {
                $entry->set_prop( picture_mapid => $u->get_mapid_from_keyword( $kw, create => 1 ) );
            }
            else {
                $entry->set_prop( picture_keyword => $kw );
            }
        }

        # now try to skip it if we already have it
        return
               if $entry_map->{ $evt->{key} }
            || $xpost_map->{ $evt->{itemid} }
            || $has{ $evt->{itemid} };

        # try to detect suspiciously similar entries
        # but first clean subject to make sure it matches what we actually inserted into the db
        # separate condition from above so that we can log that we guessed these are similar
        $evt->{subject} = $class->remap_lj_user( $data, $evt->{subject} || "" );
        my $dupecheck_key = $evt->{eventtime} . '-' . $evt->{subject};
        if ( $duplicates_map->{$dupecheck_key} ) {
            $log->(
                "Skipping entry on %s. Remote entry jitemid %d similar to local jitemid %d.",
                $evt->{eventtime}, $evt->{itemid}, $duplicates_map->{$dupecheck_key}
            );
            $has{ $evt->{itemid} } = 1;

            return;
        }

        # clean up event for LJ and remap friend groups
        my @item_errors;
        my $allowmask = $evt->{allowmask};
        my $newmask   = $class->remap_groupmask( $data, $allowmask );

        # if we are unable to determine a good groupmask, then fall back to making
        # the entry private and mark the error.
        if ( $allowmask != 1 && $newmask == 1 ) {
            $newmask = 0;
            push @item_errors, "Could not determine groups to post to.";
        }
        $evt->{allowmask} = $newmask;

        # now try to determine if we need to post this as a user
        my $posteru;
        if ( $data->{usejournal} ) {
            my ( $posterid, $fid ) = $class->get_remapped_userids( $data, $evt->{poster}, $log );

            unless ($posterid) {

                # FIXME: need a better way of totally dying...
                push @item_errors,
                    "Unable to map poster from LJ user '$evt->{poster}' to local user.";
                $status->(
                    remote_url => $evt->{url},
                    errors     => \@item_errors,
                );
                return;
            }

            $posteru = LJ::load_userid($posterid);
        }

        # we just link polls to the original site
        # FIXME: this URL should be from some method and not manually constructed
        my $event = $evt->{event};
        $event =~
            s!<.+?-poll-(\d+?)>![<a href="http://www.$data->{hostname}/poll/?id=$1">Poll #$1</a>]!g;

        if ( $event =~ m/<.+?-embed-.+?>/ ) {
            $event =~ s/<.+?-embed-.+?>//g;

            push @item_errors,
                "Entry contained an embed tag, please manually re-add the embedded content.";
        }

        if ( $event =~ m/<.+?-template-.+?>/ ) {
            $event =~ s/<.+?-template-.+?>//g;

            push @item_errors,
                "Entry contained a template tag, please manually re-add the templated content.";
        }

        $evt->{event} = $class->remap_lj_user( $data, $event );

        # actually post it
        my ( $ok, $res ) =
            DW::Worker::ContentImporter::Local::Entries->post_event( $data, $entry_map, $u,
            $posteru, $evt, \@item_errors );

        # we don't need this text anymore, so nuke it to try to save memory
        delete $evt->{event};
        delete $evt->{subject};

        # now record any errors that happened
        $status->(
            remote_url => $evt->{url},
            post_res   => $res,
            errors     => \@item_errors,
        ) if @item_errors;

    };

    # helper to load some events -- if this function does not return a true value,
    # the caller must exit (errors were encountered).
    my $fetch_events = sub {

        # let them know we're still working
        $job->grabbed_until( time() + 3600 );
        $job->save;

        $log->( 'Fetching %d items.', scalar @_ );
        $title->( 'getevents - %d to %d', $_[0], $_[-1] );

        # try to get it from the remote server
        my $hash = $class->call_xmlrpc(
            $data,
            'getevents',
            {
                ver         => 1,
                itemids     => join( ',', @_ ) . ",",
                selecttype  => 'multiple',
                lineendings => 'unix',
            }
        );

        # if we get an error, then we have to abort the import
        my $xmlrpc_fail = 'XMLRPC failure: ' . ( $hash ? $hash->{faultString} : '[unknown]' );
        $xmlrpc_fail .= " (community: $data->{usejournal})" if $data->{usejournal};
        if ( !$hash || $hash->{fault} ) {
            $temp_fail->($xmlrpc_fail);
            return 0;
        }

        # good, import this event
        $process_entry->($_) foreach @{ $hash->{events} || [] };
        return 1;
    };

    # now get the actual events
    my @toload;
    foreach my $jid ( 0 .. $maxid ) {
        push @toload, $jid
            unless exists $has{$jid} && $has{$jid};
        if ( scalar @toload == 100 ) {
            return unless $fetch_events->(@toload);
            @toload = ();
        }
    }
    if ( scalar @toload > 0 ) {
        return unless $fetch_events->(@toload);
    }

    # mark the comments mode as ready to schedule
    my $dbh = LJ::get_db_writer();
    $dbh->do(
        q{UPDATE import_items SET status = 'ready'
          WHERE userid = ? AND item IN ('lj_comments')
          AND import_data_id = ? AND status = 'init'},
        undef, $u->id, $opts->{import_data_id}
    );

    # Kick off a indexing job for this user
    if (@LJ::SPHINX_SEARCHD) {
        LJ::theschwartz()->insert_jobs(
            TheSchwartz::Job->new_from_array(
                'DW::Worker::Sphinx::Copier', { userid => $u->id, source => "importen" }
            )
        );
    }

    return $ok->();
}

sub find_prunable_items {
    my ( $class, $u, $entry_map, $xpost_map, %opts ) = @_;

    my $log            = $opts{log_sub} || sub { warn @_ };
    my $force_reimport = $opts{force_reimport};
    my $hostname       = $opts{hostname};
    my $username       = $opts{username};

    # this is an optimization.  since we never do an edit event (only post!) we will
    # never get changes anyway.  so let's remove from the list of things to sync any
    # post that we already know about.  (not that we really care, but it's much nicer
    # on people we're pulling from.)
    my %has;    # jitemids we have
    foreach my $url ( keys %$entry_map ) {

        # but first, let's skip anything that isn't from the server we are importing
        # from.  this assumes URLs never have other hostnames, so if someone were to
        # register testlivejournal.com and do an import, they will have trouble
        # importing.  if they want to do that to befunge this logic, more power to them.
        $url =~ s/-/_/g;    # makes \b work below
        next
            unless $url =~ /\Q$hostname\E/
            && $url =~ /\b$username\b/;

        unless ( $url =~ m!/(\d+)(?:\.html)?$! ) {
            $log->( 'URL %s not of expected format in prune.', $url );
            next;
        }

        # if we want a paid user or someone to get their picture keyword updated,
        # skip them here.
        next if $force_reimport;

        # yes, we can has this jitemid from the remote side
        $has{ $1 >> 8 } = 1;
    }
    $log->( 'Identified %d items we already know about (first pass).', scalar( keys %has ) );
    $log->( 'memory usage is now %dMB', LJ::gtop()->proc_mem($$)->resident / 1024 / 1024 );

    # this is another optimization.  we know crossposted entries can be removed from
    # the list of things we will import, as we generated them to begin with.
    foreach my $itemid ( keys %$xpost_map ) {
        $has{$itemid} = 1;
    }

    $log->( 'Identified %d items we already know about (second pass).', scalar( keys %has ) );
    $log->( 'memory usage is now %dMB', LJ::gtop()->proc_mem($$)->resident / 1024 / 1024 );

    my $duplicates_map =
        DW::Worker::ContentImporter::Local::Entries->get_duplicates_map( $u, \%has ) || {};
    $log->( 'Found %d items to check for duplicates.', scalar( keys %$duplicates_map ) );
    $log->( 'memory usage is now %dMB', LJ::gtop()->proc_mem($$)->resident / 1024 / 1024 );

    return ( $duplicates_map, %has );
}

1;
