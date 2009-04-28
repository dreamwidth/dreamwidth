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
# Copyright (c) 2009 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Worker::ContentImporter::LiveJournal::Comments;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

use Carp qw/ croak confess /;
use Encode qw/ encode_utf8 /;
use Time::HiRes qw/ tv_interval gettimeofday /;
use DW::Worker::ContentImporter::Local::Comments;

# these come from LJ
our $COMMENTS_FETCH_META = 10000;
our $COMMENTS_FETCH_BODY = 1000;

sub work {
    my ( $class, $job ) = @_;
    my $opts = $job->arg;
    my $data = $class->import_data( $opts->{userid}, $opts->{import_data_id} );

    eval { try_work( $class, $job, $opts, $data ); };
    if ( my $msg = $@ ) {
        $msg =~ s/\r?\n/ /gs;
        return $class->temp_fail( $data, 'lj_comments', $job, 'Failure running job: %s', $msg );
    }
}

sub try_work {
    my ( $class, $job, $opts, $data ) = @_;
    my $begin_time = [ gettimeofday() ];

    # we know that we can potentially take a while, so budget a few hours for
    # the import job before someone else comes in to snag it
    $job->grabbed_until( time() + 3600*12 );
    $job->save;

    # failure wrappers for convenience
    my $fail      = sub { return $class->fail( $data, 'lj_comments', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_comments', $job ); };
    my $temp_fail = sub { return $class->temp_fail( $data, 'lj_comments', $job, @_ ); };
    my $status    = sub { return $class->status( $data, 'lj_comments', { @_ } ); };

    # logging sub
    my ( $logfile, $last_log_time );
    my $log = sub {
        $last_log_time ||= [ gettimeofday() ];

        unless ( $logfile ) {
            mkdir "$LJ::HOME/logs/imports";
            mkdir "$LJ::HOME/logs/imports/$opts->{userid}";
            open $logfile, ">>$LJ::HOME/logs/imports/$opts->{userid}/$opts->{import_data_id}.lj_comments.$$"
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

        $0 = sprintf( 'content-importer [comments: %s(%d)%s]', $u->user, $u->id, $msg );
    };
    $title->();

    # this will take a entry_map (old URL -> new jitemid) and convert it into a jitemid map (old jitemid -> new jitemid)
    my $entry_map = DW::Worker::ContentImporter::Local::Entries->get_entry_map( $u ) || {};
    $log->( 'Loaded entry map with %d entries.', scalar( keys %$entry_map ) );

    # now backfill into jitemid_map
    my $jitemid_map = {};
    foreach my $url ( keys %$entry_map ) {
        # this works, see the Entries importer for more information
        my $turl = $url;
        $turl =~ s/-/_/g; # makes \b work below
        next unless $turl =~ /\Q$data->{hostname}\E/ &&
                    $turl =~ /\b$data->{username}\b/;

        my $jitemid = $1 >> 8
            if $url =~ m!/(\d+)\.html$!;
        $jitemid_map->{$jitemid} = $entry_map->{$url};
    }

    # this will take a talk_map (old URL -> new jtalkid) and convert it to a jtalkid map (old jtalkid -> new jtalkid)
    my $talk_map = DW::Worker::ContentImporter::Local::Comments->get_comment_map( $u ) || {};
    $log->( 'Loaded comment map with %d entries.', scalar( keys %$talk_map ) );

    # now reverse it as above
    my $jtalkid_map = {};
    foreach my $url ( keys %$talk_map ) {
        # this works, see the Entries importer for more information
        my $turl = $url;
        $turl =~ s/-/_/g; # makes \b work below
        next unless $turl =~ /\Q$data->{hostname}\E/ &&
                    $turl =~ /\b$data->{username}\b/;

        my $jtalkid = $1 >> 8
            if $url =~ m!thread=(\d+)$!;
        $jtalkid_map->{$jtalkid} = $talk_map->{$url};
    }

    # parameters for below
    my ( %meta, @userids, $identity_map, $was_external_user );
    my ( $maxid, $server_max_id, $server_next_id, $lasttag ) = ( 0, 0, 1, '' );

    # setup our parsing function
    my $meta_handler = sub {
        # this sub actually processes incoming meta information
        $lasttag = $_[1];
        shift; shift;      # remove the Expat object and tag name
        my %temp = ( @_ ); # take the rest into our humble hash

        # if we were last getting a comment, start storing the info
        if ( $lasttag eq 'comment' ) {
            # get some data on a comment
            $meta{$temp{id}} = {
                id => $temp{id},
                posterid => $temp{posterid}+0,
                state => $temp{state} || 'A',
            };

        } elsif ( $lasttag eq 'usermap' && ! exists $identity_map->{$temp{id}} ) {
            push @userids, $temp{id};

            my ( $local_oid, $local_fid ) = $class->get_remapped_userids( $data, $temp{user} );
            $identity_map->{$temp{id}} = $local_oid;
            $was_external_user->{$temp{id}} = 1
                if $temp{user} =~ m/^ext_/; # If the remote username starts with ext_ flag it as external

            $log->( 'Mapped remote %s(%d) to local userid %d.', $temp{user}, $temp{id}, $local_oid );
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
    while ( defined $server_next_id && $server_next_id =~ /^\d+$/ ) {
        $log->( 'Fetching metadata; max_id = %d, next_id = %d.', $server_max_id || 0, $server_next_id || 0 );

        $title->( 'meta-fetch from id %d', $server_next_id );
        my $content = $class->do_authed_comment_fetch(
            $data, 'comment_meta', $server_next_id, $COMMENTS_FETCH_META
        );
        return $temp_fail->( 'Error fetching comment metadata from server.' )
            unless $content;

        $server_next_id = undef;

        # now we want to XML parse this
        my $parser = new XML::Parser(
            Handlers => {
                Start => $meta_handler,
                Char  => $meta_content,
                End   => $meta_closer
            }
        );
        $parser->parse( $content );
    }
    $log->( 'Finished fetching metadata.' );

    # body handling section now
    my ( $lastid, $curid, @tags ) = ( 0, 0 );

    # setup our handlers for body XML info
    my $body_handler = sub {
        # this sub actually processes incoming body information
        $lasttag = $_[1];
        push @tags, $lasttag;
        shift; shift;      # remove the Expat object and tag name
        my %temp = ( @_ ); # take the rest into our humble hash
        if ( $lasttag eq 'comment' ) {
            # get some data on a comment
            $curid = $temp{id};
            $meta{$curid}{parentid} = $temp{parentid}+0;
            $meta{$curid}{jitemid} = $temp{jitemid}+0;
        }
    };
    my $body_closer = sub {
        # we hit a closing tag so we're not in a tag anymore
        my $tag = pop @tags;
        $lasttag = $tags[0];
    };
    my $body_content = sub {
        # this grabs data inside of comments: body, subject, date
        return unless $curid;
        return unless $lasttag =~ /(?:body|subject|date)/;
        $meta{$curid}{$lasttag} .= $_[1];
        # have to .= it, because the parser will split on punctuation such as an apostrophe
        # that may or may not be in the data stream, and we won't know until we've already
        # gotten some data
    };

    # start looping to fetch all of the comment bodies
    while ( $lastid < $server_max_id ) {
        $log->( 'Fetching bodydata; last_id = %d, max_id = %d.', $lastid || 0, $server_max_id || 0 );

        $title->( 'body-fetch from id %d', $lastid+1 );
        my $content = $class->do_authed_comment_fetch(
            $data, 'comment_body', $lastid+1, $COMMENTS_FETCH_BODY
        );
        return $temp_fail->( 'Error fetching comment body data from server.' )
            unless $content;

        # now we want to XML parse this
        my $parser = new XML::Parser(
            Handlers => {
                Start => $body_handler,
                Char  => $body_content,
                End   => $body_closer
            }
        );
        $parser->parse( $content );

        # the exporter should always return the maximum number of items, so loop again.  of course,
        # this will fail nicely as soon as some site we're importing from reduces the max items
        # they return due to load.  http://community.livejournal.com/changelog/5907095.html
        $lastid += $COMMENTS_FETCH_BODY;
    }

    # now iterate over each comment and build the nearly final structure
    foreach my $comment ( values %meta ) {

        # if we weren't able to map to a jitemid (last entry import a while ago?)
        # or some other problem, log it and bail
        unless ( $jitemid_map->{$comment->{jitemid}} ) {
            $comment->{skip} = 1;
            $log->( 'NO MAPPED ENTRY: remote values: jitemid %d, posterid %d, jtalkid %d.',
                    $comment->{jitemid}, $comment->{posterid}, $comment->{id} );
            next;
        }

        $comment->{source} = $data->{hostname}
            if $was_external_user->{$comment->{posterid}};

        # basic mappings
        $comment->{posterid} = $identity_map->{$comment->{posterid}};
        $comment->{jitemid} = $jitemid_map->{$comment->{jitemid}};
        $comment->{orig_id} = $comment->{id};

        # unresolved comments means we haven't got the parent in the database
        # yet so we can't post this one
        $comment->{unresolved} = 1
            if $comment->{parentid};

        # the reverse of unresolved, tell the parent it has visible children
        $meta{$comment->{parentid}}->{has_children} = 1
            if exists $meta{$comment->{parentid}} &&
               $comment->{parentid} && $comment->{state} ne 'D';

        # remap content (user links) then remove embeds/templates
        my $body = $class->remap_lj_user( $data, $comment->{body} );
        $body =~ s/<.+?-embed-.+?>/[Embedded content removed during import.]/g;
        $body =~ s/<.+?-template-.+?>/[Templated content removed during import.]/g;
        $comment->{body} = $body;

        # now let's do some encoding, just in case the input we get is in some other
        # character encoding
        $comment->{body} = encode_utf8( $comment->{body} || '' );
        $comment->{subject} = encode_utf8( $comment->{subject} || '' );
    }

    # variable setup for the database work
    my @to_import = sort { ( $a->{id}+0 ) <=> ( $b->{id}+0 ) } values %meta;
    my $had_unresolved = 1;

    # This loop should never need to run through more then once
    # but, it will *if* for some reason a comment comes before its parent
    # which *should* never happen, but I'm handling it anyway, just in case.
    $title->( 'posting %d comments', scalar( @to_import ) );
    while ( $had_unresolved ) {

        # variables, and reset
        my ( $ct, $ct_unresolved ) = ( 0, 0 );
        $had_unresolved = 0;

        # now doing imports!
        foreach my $comment ( @to_import ) {
            next if $comment->{skip};

            $title->( 'posting %d/%d comments', $comment->{orig_id}, scalar( @to_import ) );
            $log->( "Attempting to import remote id %d, parentid %d, state %s.",
                    $comment->{orig_id}, $comment->{parentid}, $comment->{state} );

            # rules we might skip a content with
            next if $comment->{done}; # Skip this comment if it was already imported this round
            next if $jtalkid_map->{$comment->{orig_id}}; # Or on a previous import round

            # now we know this one is going in the database
            $ct++;

            # try to resolve
            if ( $comment->{unresolved} ) {
                # lets see if this is resolvable at the moment
                # A resolvable comment is a comment that's parent is already in the DW database
                # and an unresolved comment is a comment that has a parent that is currently not in the database.
                if ( $jtalkid_map->{$comment->{parentid}} ) {
                    $comment->{parentid} = $jtalkid_map->{$comment->{parentid}};
                    $comment->{unresolved} = 0;

                    $log->( 'Resolved unresolved comment to local parentid %d.',
                            $comment->{parentid} );

                } else {
                    # guess we couldn't resolve it :( next pass!
                    $ct_unresolved++;
                    $had_unresolved = 1;

                    $log->( 'Failed to resolve comment.' );

                    next;
                }
            }

            # if we get here we're good to insert into the database
            my $err = "";
            my $talkid = DW::Worker::ContentImporter::Local::Comments->insert_comment( $u, $comment, \$err );
            if ( $talkid ) {
                $log->( 'Successfully imported source %d to new jtalkid %d.', $comment->{id}, $talkid );
            } else {
                $log->( 'Failed to import comment %d: %s.', $comment->{id}, $err );
                return $temp_fail->( 'Failure importing comment: %s.', $err );
            }

            # store this information
            $jtalkid_map->{$comment->{id}} = $talkid;
            $comment->{id} = $talkid;
            $comment->{done} = 1;
        }

        # sanity check.  this happens from time to time when, for example, a comment
        # is deleted but the chain of comments underneath it is never actually removed.
        # given that the codebase doesn't use foreign keys and transactions, this can
        # happen and we have to deal with it gracefully.  log it.
        if ( $ct == $ct_unresolved && $had_unresolved ) {
            $log->( 'WARNING: User had %d unresolvable comments.', $ct_unresolved );

            # set this to false so that we fall out of the main loop.
            $had_unresolved = 0;
        }
    }

    return $ok->();
}


sub do_authed_comment_fetch {
    my ( $class, $data, $mode, $startid, $numitems ) = @_;

    # if we don't have a session, then let's generate one
    $data->{_session} ||= $class->get_lj_session( $data );

    # hit up the server with the specified information and return the raw content
    my $ua = LWP::UserAgent->new;
    my $request = HTTP::Request->new( GET => "http://www.$data->{hostname}/export_comments.bml?get=$mode&startid=$startid&numitems=$numitems" );
    $request->push_header( Cookie => "ljsession=$data->{_session}" );

    # try to get the response
    my $response = $ua->request( $request );
    return if $response->is_error;

    # now get the content
    my $xml = $response->content;
    return $xml if $xml;

    # total failure...
    return undef;
}


1;
