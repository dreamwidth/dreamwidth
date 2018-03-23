#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal::Comments
#
# Importer worker for LiveJournal-based sites comments.
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

package DW::Worker::ContentImporter::LiveJournal::Comments;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

use Carp qw/ croak confess /;
use Digest::MD5 qw/ md5_hex /;
use Encode qw/ encode_utf8 /;
use Time::HiRes qw/ tv_interval gettimeofday /;
use DW::XML::Parser;
use DW::Worker::ContentImporter::Local::Comments;

# to save memory, we use arrays instead of hashes.
use constant C_id => 0;
use constant C_remote_posterid => 1;
use constant C_state => 2;
use constant C_remote_parentid => 3;
use constant C_remote_jitemid => 4;
use constant C_body => 5;
use constant C_subject => 6;
use constant C_date => 7;
use constant C_props => 8;
use constant C_source => 9;
use constant C_entry_source => 10;
use constant C_orig_id => 11;
use constant C_done => 12;
use constant C_body_fixed => 13;
use constant C_local_parentid => 14;
use constant C_local_jitemid => 15;
use constant C_local_posterid => 16;

# these come from LJ
our $COMMENTS_FETCH_META = 10000;
our $COMMENTS_FETCH_BODY = 500;

sub work {
    # VITALLY IMPORTANT THAT THIS IS CLEARED BETWEEN JOBS
    %DW::Worker::ContentImporter::LiveJournal::MAPS = ();
    DW::Worker::ContentImporter::Local::Comments->clear_caches();
    LJ::start_request();

    my ( $class, $job ) = @_;
    my $opts = $job->arg;
    my $data = $class->import_data( $opts->{userid}, $opts->{import_data_id} );

    return $class->decline( $job ) unless $class->enabled( $data );

    eval { try_work( $class, $job, $opts, $data ); };
    if ( my $msg = $@ ) {
        $msg =~ s/\r?\n/ /gs;

        open FILE, ">$LJ::HOME/logs/imports/$opts->{userid}/$opts->{import_data_id}.lj_comments.$$.failure";
        print FILE "FAILURE: $msg";
        close FILE;

        return $class->temp_fail( $data, 'lj_comments', $job, 'Failure running job: %s', $msg );
    }

    # FIXME: We leak memory, so exit to reclaim it. Hack.
    exit 0;
}

sub new_comment {
    my ( $id, $posterid, $state ) = @_;
    return [ undef, $posterid+0, $state, undef, undef, undef, undef, undef, {},
             undef, undef, $id+0, undef, 0, undef, undef, undef ];
}

sub hashify {
    return {
        id => $_[0]->[C_id],
        posterid => $_[0]->[C_local_posterid],
        state => $_[0]->[C_state],
        parentid => $_[0]->[C_local_parentid],
        jitemid => $_[0]->[C_local_jitemid],
        body => $_[0]->[C_body],
        subject => $_[0]->[C_subject],
        date => $_[0]->[C_date],
        props => $_[0]->[C_props],
        source => $_[0]->[C_source],
        entry_source => $_[0]->[C_entry_source],
        orig_id => $_[0]->[C_orig_id],
        done => $_[0]->[C_done],
        body_fixed => $_[0]->[C_body_fixed],
    };
}

sub try_work {
    my ( $class, $job, $opts, $data ) = @_;
    my $begin_time = [ gettimeofday() ];

    # we know that we can potentially take a while, so budget a few hours for
    # the import job before someone else comes in to snag it
    $job->grabbed_until( time() + 3600*72 );
    $job->save;

    # failure wrappers for convenience
    my $fail      = sub { return $class->fail( $data, 'lj_comments', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_comments', $job ); };
    my $temp_fail = sub { return $class->temp_fail( $data, 'lj_comments', $job, @_ ); };
    my $status    = sub { return $class->status( $data, 'lj_comments', { @_ } ); };

    # logging sub
    my ( $logfile, $last_log_time );
    $logfile = $class->start_log( "lj_comments", userid => $opts->{userid}, import_data_id => $opts->{import_data_id} )
        or return $temp_fail->( 'Internal server error creating log.' );

    my $log = sub {
        $last_log_time ||= [ gettimeofday() ];

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
    $log->( 'memory usage is now %dMB', LJ::gtop()->proc_mem($$)->resident/1024/1024 );

    # title munging
    my $title = sub {
        my $msg = sprintf( shift(), @_ );
        $msg = " $msg" if $msg;

        $0 = sprintf( 'content-importer [comments: %s(%d)%s]', $u->user, $u->id, $msg );
    };
    $title->();

    # this will take a entry_map (old URL -> new jitemid) and convert it into a jitemid map (old jitemid -> new jitemid)
    my $entry_map = DW::Worker::ContentImporter::Local::Entries->get_entry_map( $u ) || {};
    $log->( 'Loaded entry map with %d entries.', scalar( keys %$entry_map ) );
    $log->( 'memory usage is now %dMB', LJ::gtop()->proc_mem($$)->resident/1024/1024 );

    # now backfill into jitemid_map
    my ( %entry_source, %jitemid_map );
    $log->( 'Filtering parameters: hostname=[%s], username=[%s].', $data->{hostname}, $data->{username} );
    foreach my $url ( keys %$entry_map ) {
        # this works, see the Entries importer for more information
        my $turl = $url;
        $turl =~ s/-/_/g; # makes \b work below
        #$log->( 'Filtering entry URL: %s', $turl );
        next unless $turl =~ /\Q$data->{hostname}\E/ &&
                    ( $turl =~ /\b$data->{username}\b/ ||
                        ( $data->{usejournal} && $turl =~ /\b$data->{usejournal}\b/ ) );

        if ( $url =~ m!/(\d+)(?:\.html)?$! ) {
            my $jitemid = $1 >> 8;
            $jitemid_map{$jitemid} = $entry_map->{$url};
            $entry_source{$jitemid_map{$jitemid}} = $url;
        }
    }
    $log->( 'Entry map has %d entries post-prune.', scalar( keys %$entry_map ) );
    $log->( 'memory usage is now %dMB', LJ::gtop()->proc_mem($$)->resident/1024/1024 );

    # now prepare the xpost map
    my $xpost_map = $class->get_xpost_map( $u, $data ) || {};
    $log->( 'Loaded xpost map with %d entries.', scalar( keys %$xpost_map ) );
    $log->( 'memory usage is now %dMB', LJ::gtop()->proc_mem($$)->resident/1024/1024 );

    foreach my $jitemid ( keys %$xpost_map ) {
        $jitemid_map{$jitemid} = $xpost_map->{$jitemid};
        $entry_source{$jitemid_map{$jitemid}} = "CROSSPOSTER " . $data->{hostname} . " " . $data->{username} . " $jitemid ";
    }

    # this will take a talk_map (old URL -> new jtalkid) and convert it to a jtalkid map (old jtalkid -> new jtalkid)
    my $talk_map = DW::Worker::ContentImporter::Local::Comments->get_comment_map( $u ) || {};
    $log->( 'Loaded comment map with %d entries.', scalar( keys %$talk_map ) );
    $log->( 'memory usage is now %dMB', LJ::gtop()->proc_mem($$)->resident/1024/1024 );

    # now reverse it as above
    my $jtalkid_map = {};
    foreach my $url ( keys %$talk_map ) {
        # this works, see the Entries importer for more information
        my $turl = $url;
        $turl =~ s/-/_/g; # makes \b work below
        #$log->( 'Filtering comment URL: %s', $turl );
        next unless $turl =~ /\Q$data->{hostname}\E/ &&
                    ( $turl =~ /\b$data->{username}\b/ ||
                        ( $data->{usejournal} && $turl =~ /\b$data->{usejournal}\b/ ) );

        if ( $url =~ m!(?:thread=|/)(\d+)$! ) {
            my $jtalkid = $1 >> 8;
            $jtalkid_map->{$jtalkid} = $talk_map->{$url};
        }
    }

    # for large imports, the two maps are big (contains URLs), so let's drop it
    # since we're never going to use it again. PS I don't actually know if this
    # frees the memory, but I'm hoping it does.
    undef $talk_map;
    undef $entry_map;
    undef $xpost_map;

    # parameters for below
    my ( %meta, %identity_map, %was_external_user );
    my ( $maxid, $server_max_id, $server_next_id, $nextid, $lasttag ) = ( 0, undef, 1, 0, '' );
    my @fail_errors;

    # setup our parsing function
    my $meta_handler = sub {
        # this sub actually processes incoming meta information
        $lasttag = $_[1];
        shift; shift;      # remove the Expat object and tag name
        my %temp = ( @_ ); # take the rest into our humble hash

        # if we were last getting a comment, start storing the info
        if ( $lasttag eq 'comment' ) {
            # get some data on a comment
            $meta{$temp{id}} = new_comment( $temp{id}, $temp{posterid}+0, $temp{state} || 'A' );

            # Some servers have old code and don't return the nextid tag, so
            # we have to track the best ID we've seen and use it later.
            $nextid = $temp{id} if $temp{id} > $nextid;

        } elsif ( $lasttag eq 'usermap' && ! exists $identity_map{$temp{id}} ) {
            my ( $local_oid, $local_fid ) = $class->get_remapped_userids( $data, $temp{user}, $log );

            # we want to fail if we weren't able to create a local user, because this would otherwise be mistakenly posted as anonymous
            push @fail_errors, "Unable to map comment poster from $data->{hostname} user '$temp{user}' to local user"
                unless $local_oid;

            $identity_map{$temp{id}} = $local_oid;
            $was_external_user{$temp{id}} = 1
                if $temp{user} =~ m/^ext_/; # If the remote username starts with ext_ flag it as external

            $log->( 'Mapped remote %s(%d) to local userid %d.', $temp{user}, $temp{id}, $local_oid )
                if $local_oid;
        }
    };
    my $meta_closer = sub {
        # we hit a closing tag so we're not in a tag anymore
        $lasttag = '';
    };
    my $meta_content = sub {
        # if we're in a maxid tag, we want to save that value so we know how much further
        # we have to go in downloading meta info
        return undef
            unless $lasttag eq 'maxid' ||
                   $lasttag eq 'nextid';

        # save these values for later
        $server_max_id = $_[1] + 0 if $lasttag eq 'maxid';
        $server_next_id = $_[1] + 0 if $lasttag eq 'nextid';
    };

    # hit up the server for metadata
    while ( defined $server_next_id && $server_next_id =~ /^\d+$/ &&
            ( ! defined $server_max_id || $server_next_id <= $server_max_id ) ) {
        # let them know we're still working
        $job->grabbed_until( time() + 3600 );
        $job->save;

        $log->( 'Fetching metadata; max_id = %d, next_id = %d.', $server_max_id || 0, $server_next_id || 0 );

        $title->( 'meta-fetch from id %d', $server_next_id );
        my $content = $class->do_authed_comment_fetch(
            $data, 'comment_meta', $server_next_id, $COMMENTS_FETCH_META, $log
        );
        return $temp_fail->( 'Error fetching comment metadata from server.' )
            unless $content;

        $server_next_id = undef;

        # now we want to XML parse this
        my $parser = new DW::XML::Parser(
            Handlers => {
                Start => $meta_handler,
                Char  => $meta_content,
                End   => $meta_closer
            }
        );
        $parser->parse( $content );

        return $temp_fail->( join( "\n", map { " * $_" } @fail_errors ) )
            if @fail_errors;

        # this is the best place to test for too many comments. if this site is limiting
        # the comment imports for some reason or another, we can bail here.
        return $fail->( $LJ::COMMENT_IMPORT_ERROR || 'Too many comments to import.' )
            if defined $LJ::COMMENT_IMPORT_MAX && defined $server_max_id &&
                $server_max_id > $LJ::COMMENT_IMPORT_MAX;

        # Now we need to ensure that we get a proper nextid. If it's an old
        # remote, then they won't send <nextid> in the metadata. :-(
        $server_next_id = $nextid + 1
            if defined $nextid && $nextid > 0 && ! defined $server_next_id;
    }
    $log->( 'Finished fetching metadata.' );
    $log->( 'memory usage is now %dMB', LJ::gtop()->proc_mem($$)->resident/1024/1024 );

    # as an optimization, keep track of which comments are on the "to do" list
    my %in_flight;

    # this method is called when we have some comments to post. this will do a best effort
    # attempt to post all comments that are filled in. if this returns 0, the caller should
    # consider the import failed and exit.
    my $post_comments = sub {
        $log->( 'post sub starting with %d comments in flight', scalar( keys %in_flight ) );

        # now iterate over each comment and build the nearly final structure
        foreach my $id ( sort keys %in_flight ) {
            my $comment = $meta{$id};
            next unless defined $comment->[C_done]; # must be defined
            next if $comment->[C_done] || $comment->[C_body_fixed];

            # where this comment comes from
            $comment->[C_source] = $data->{hostname}
                if $was_external_user{$comment->[C_remote_posterid]};

            # basic mappings
            $comment->[C_local_posterid] = $identity_map{$comment->[C_remote_posterid]}+0;
            $comment->[C_local_jitemid] = $jitemid_map{$comment->[C_remote_jitemid]}+0;
            $comment->[C_entry_source] = $entry_source{$comment->[C_local_jitemid]};

            # remap content (user links) then remove embeds/templates
            my $body = $class->remap_lj_user( $data, $comment->[C_body] );
            $body =~ s/<.+?-embed-.+?>/[Embedded content removed during import.]/g;
            $body =~ s/<.+?-template-.+?>/[Templated content removed during import.]/g;
            $comment->[C_body] = $body;

            # now let's do some encoding, just in case the input we get is in some other
            # character encoding
            $comment->[C_body] = encode_utf8( $comment->[C_body] || '' );
            $comment->[C_subject] = encode_utf8( $comment->[C_subject] || '' );
            foreach my $prop ( keys %{$comment->[C_props]} ) {
                $comment->[C_props]->{$prop} = encode_utf8( $comment->[C_props]->{$prop} );
            }

            # this body is done
            $comment->[C_body_fixed] = 1;
        }

        # variable setup for the database work
        my @to_import = sort { ( $a->[C_orig_id]+0 ) <=> ( $b->[C_orig_id]+0 ) }
                        grep { defined $_->[C_done] && $_->[C_done] == 0 && $_->[C_body_fixed] == 1 }
                        map { $meta{$_} }
                        keys %in_flight;
        $title->( 'posting %d comments', scalar( @to_import ) );

        # let's do some batch loads of the users and entries we're going to need
        my ( %jitemids, %userids );
        foreach my $comment ( @to_import ) {
            $jitemids{$comment->[C_local_jitemid]} = 1;
            $userids{$comment->[C_local_posterid]} = 1
                if defined $comment->[C_local_posterid];
        }
        DW::Worker::ContentImporter::Local::Comments->precache( $u, [ keys %jitemids ], [ keys %userids ] );

        # now doing imports!
        foreach my $comment ( @to_import ) {
            next if $comment->[C_done];

            # status output update
            $title->( 'posting %d/%d comments [%d]', $comment->[C_orig_id], $server_max_id, scalar( @to_import ) );
            $log->( "Attempting to import remote id %d, parentid %d, state %s.",
                    $comment->[C_orig_id], $comment->[C_remote_parentid], $comment->[C_state] );

            # if this comment already exists, we might need to update it, however
            my $err = "";
            if ( my $jtalkid = $jtalkid_map->{$comment->[C_orig_id]} ) {
                if ( $comment->[C_state] ne 'D' ) {
                    $log->( 'Comment already exists, passing to updater.' );

                    $comment->[C_local_parentid] = $jtalkid_map->{$comment->[C_remote_parentid]}+0;
                    $comment->[C_id] = $jtalkid;

                    DW::Worker::ContentImporter::Local::Comments->update_comment( $u, hashify( $comment ), \$err );
                    $log->( 'ERROR: %s', $err ) if $err;
                } else {
                    $log->( 'Comment exists but is deleted, skipping.' );
                }

                $comment->[C_done] = 1;
                next;
            }

            # due to the ordering, by the time we're here we should be guaranteed to have
            # our parent comment. if we don't, bail out on this comment and mark it as done.
            if ( $comment->[C_remote_parentid] && !defined $comment->[C_local_parentid] ) {
                my $lpid = $jtalkid_map->{$comment->[C_remote_parentid]};
                unless ( defined $lpid ) {
                    $log->( 'ERROR: Failed to map remote parent %d.', $comment->[C_remote_parentid] );
                    next;
                }
                $comment->[C_local_parentid] = $lpid+0;
            } else {
                $comment->[C_local_parentid] = 0; # top level
            }
            $log->( 'Remote parent %d is local parent %d for orig_id=%d.',
                    $comment->[C_remote_parentid], $comment->[C_local_parentid], $comment->[C_orig_id] )
                if $comment->[C_remote_parentid];

            # if we get here we're good to insert into the database
            my $talkid = DW::Worker::ContentImporter::Local::Comments->insert_comment( $u, hashify( $comment ), \$err );
            if ( $talkid ) {
                $log->( 'Successfully imported remote id %d to new jtalkid %d.', $comment->[C_orig_id], $talkid );
            } else {
                $log->( 'Failed to import comment %d: %s.', $comment->[C_orig_id], $err );
                $temp_fail->( 'Failure importing comment: %s.', $err );
                return 0;
            }

            # store this information
            $jtalkid_map->{$comment->[C_orig_id]} = $talkid;
            $comment->[C_id] = $talkid;
            $comment->[$_] = undef # free up some memory
                foreach ( C_props, C_body, C_subject );
            $comment->[C_done] = 1;
        }

        # remove things that have finished from the in_flight list
        delete $in_flight{$_}
            foreach grep { defined $meta{$_}->[C_done] && $meta{$_}->[C_done] == 1 }
                    keys %in_flight;
        $log->( 'end of post sub has %d comments in flight', scalar( keys %in_flight ) );
        $log->( 'memory usage is now %dMB', LJ::gtop()->proc_mem($$)->resident/1024/1024 );
        return 1;
    };

    # body handling section now
    my ( $lastid, $curid, $lastprop, @tags ) = ( 0, 0, undef );

    # setup our handlers for body XML info
    my $body_handler = sub {
        # this sub actually processes incoming body information
        $lasttag = $_[1];
        push @tags, $lasttag;
        shift; shift;      # remove the Expat object and tag name
        my %temp = ( @_ ); # take the rest into our humble hash
        if ( $lasttag eq 'comment' ) {
            # get some data on a comment
            $curid = $temp{id}+0;
            $lastid = $curid if $curid > $lastid;
            $meta{$curid}->[C_remote_parentid] = $temp{parentid}+0;
            $meta{$curid}->[C_remote_jitemid] = $temp{jitemid}+0;
        } elsif ( $lasttag eq 'property' ) {
            $lastprop = $temp{name};
        }
    };
    my $body_closer = sub {
        # we hit a closing tag so we're not in a tag anymore
        my $tag = pop @tags;
        $lasttag = $tags[0];
        $lastprop = undef;
        if ( $curid && ! defined $meta{$curid}->[C_done] ) {
            $meta{$curid}->[C_done] = 0;
            $in_flight{$curid} = 1;
        }
    };
    my $body_content = sub {
        # this grabs data inside of comments: body, subject, date, properties
        return unless $curid;

        # have to append to it, because the parser will split on punctuation such as an apostrophe
        # that may or may not be in the data stream, and we won't know until we've already gotten
        # some data
        if ( $lasttag =~ /(?:body|subject|date)/ ) {
            my $arrid = { body => 5, subject => 6, date => 7 }->{$lasttag};
            $meta{$curid}->[$arrid] .= $_[1];
        } elsif ( $lastprop && $lasttag eq 'property' ) {
            $meta{$curid}->[C_props]->{$lastprop} .= $_[1];
        }
    };

    # start looping to fetch all of the comment bodies
    while ( $lastid < $server_max_id ) {
        # let them know we're still working
        $job->grabbed_until( time() + 3600 );
        $job->save;

        $log->( 'Fetching bodydata; last_id = %d, max_id = %d.', $lastid || 0, $server_max_id || 0 );

        my ( $reset_lastid, $reset_curid ) = ( $lastid, $curid );

        $title->( 'body-fetch from id %d', $lastid+1 );
        my $content = $class->do_authed_comment_fetch(
            $data, 'comment_body', $lastid+1, $COMMENTS_FETCH_BODY, $log
        );
        return $temp_fail->( 'Error fetching comment body data from server.' )
            unless $content;

        # now we want to XML parse this
        my $parser = new DW::XML::Parser(
            Handlers => {
                Start => $body_handler,
                Char  => $body_content,
                End   => $body_closer
            }
        );

        # have to do this in an eval
        eval {
            $parser->parse( $content );
        };
        if ( $@ ) {
            # this error typically means the encoding is bad.  not sure how this happens,
            # it's probably just on a very, very old comment?
            $log->( 'Parse failure: %s', $@ );
            if ( $@ =~ /token/ ) {

                # reset for another body pass
                ( $lastid, $curid ) = ( $reset_lastid, $reset_curid );
                @tags = ();

                # reset all text so we don't get it double posted
                $log->( 'Resetting comment bodies of in-flight data.' );
                foreach my $id ( keys %in_flight ) {
                    $meta{$id}->[$_] = undef
                        foreach ( C_subject, C_body, C_date, C_props );
                }

                # and now filter.  note that we're assuming this is ISO-8859-1, as that's a
                # very likely guess.  if it's not that, we have problems.
                $content = LJ::ConvUTF8->to_utf8( 'ISO-8859-1', $content );
                $parser->parse( $content );

            } else {
                # can't handle, pass it up
                $log->( 'Ultimate failure. Bailing out!' );
                die $@;
            }
        }

        # We increment lastid during our fetches so we should walk nicely, but
        # if we didn't move at least N comments forward, then increment by
        # that value so we can keep walking.
        $log->( 'lastid = %d, reset_lastid = %d', $lastid, $reset_lastid );
        $lastid = $reset_lastid + $COMMENTS_FETCH_BODY
            if $lastid - $reset_lastid < $COMMENTS_FETCH_BODY;

        # now we've got some body text, try to post these comments. if we can do that, we can clear
        # them from memory to reduce how much we're storing.
        return unless $post_comments->();
    }

    # now we have the final post loop...
    return unless $post_comments->();
    $log->( 'memory usage is now %dMB', LJ::gtop()->proc_mem($$)->resident/1024/1024 );

    # Kick off an indexing job for this user
    if ( @LJ::SPHINX_SEARCHD ) {
        LJ::theschwartz()->insert_jobs(
            TheSchwartz::Job->new_from_array( 'DW::Worker::Sphinx::Copier', { userid => $u->id, source => "importcm" } )
        );
    }

    return $ok->();
}


sub do_authed_comment_fetch {
    my ( $class, $data, $mode, $startid, $numitems, $log ) = @_;
    my $authas = $data->{usejournal} ? "&authas=$data->{usejournal}" : '';
    my $url = "http://www.$data->{hostname}/export_comments.bml?get=$mode&startid=$startid&numitems=$numitems&props=1$authas";

    # see if the file is cached and recent. this is mostly a hack useful for debugging
    # when something goes bad, or if we somehow get stuck in a loop. at least we won't
    # unintentionally DoS the target.
    my $md5 = md5_hex( $url . ($data->{user} || $data->{username}) . ($data->{usejournal} || '') );
    my $fn = "$LJ::HOME/logs/imports/$data->{userid}/$md5.xml";
    my $rv = open FILE, "<$fn";
    if ( $rv ) {
        $log->( 'Using cached file %s.xml', $md5 );

        local $/ = undef;
        my $ret = <FILE>;
        close FILE;
        return $ret;
    }

    # if we don't have a session, then let's generate one
    $data->{_session} ||= $class->get_lj_session( $data );

    # hit up the server with the specified information and return the raw content
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new( GET => $url );
    $request->push_header( Cookie => "ljsession=$data->{_session}" );

    # try to get the response
    my $response = $ua->request( $request );
    return if $response->is_error;

    # now get the content
    my $xml = $response->content;
    if ( $xml ) {
        $log->( 'Writing cache file %s.xml', $md5 );

        open FILE, ">$fn";
        print FILE $xml;
        close FILE;
        return $xml;
    }

    # total failure...
    return undef;
}


1;
