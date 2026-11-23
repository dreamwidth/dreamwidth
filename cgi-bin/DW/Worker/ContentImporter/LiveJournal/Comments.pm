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

use Encode qw/ encode_utf8 /;
use DW::Importer::Source::LiveJournal::Keys qw( index_entries index_comments crosspost_source );
use DW::Importer::Threading;
use DW::Importer::Transform::LJMarkup qw( comment_text );

# importing comments leaks memory, so the worker process exits afterwards to reclaim it
sub exit_after_job { 1 }

sub run {
    my ( $class,  $ctx )  = @_;
    my ( $data,   $job )  = ( $ctx->data, $ctx->job );
    my ( $source, $sink ) = ( $class->source_for($ctx), $ctx->sink );

    # we know that we can potentially take a while, so budget a few hours for
    # the import job before someone else comes in to snag it
    $job->grabbed_until( time() + 3600 * 72 );
    $job->save;

    my $log   = sub { return $ctx->log(@_); };
    my $title = sub { return $ctx->title(@_); };

    # the entries we have, from the remote entry id to the local jitemid, and the key each
    # was stored under, which its comments' keys are built from
    my $entry_map = $sink->entry_map;
    $log->( 'Loaded entry map with %d entries.', scalar( keys %$entry_map ) );
    $log->(
        'Filtering parameters: hostname=[%s], username=[%s].',
        $data->{hostname}, $data->{username}
    );
    my $entries =
        index_entries( $entry_map, $data->{hostname}, $data->{username}, $data->{usejournal} );
    my ( %jitemid_map, %entry_source );
    %jitemid_map  = %{ $entries->{by_remote_id} };
    %entry_source = %{ $entries->{source_of} };
    $log->( 'Entry map has %d entries post-prune.', scalar( keys %jitemid_map ) );

    # now prepare the xpost map
    my $xpost_map = $sink->xpost_map( $data->{hostname}, $data->{username} ) || {};
    $log->( 'Loaded xpost map with %d entries.', scalar( keys %$xpost_map ) );

    foreach my $jitemid ( keys %$xpost_map ) {
        $jitemid_map{$jitemid} = $xpost_map->{$jitemid};
        $entry_source{ $jitemid_map{$jitemid} } =
            crosspost_source( $data->{hostname}, $data->{username}, $jitemid );
    }

    # the comments we already have, from the remote comment id to the local jtalkid
    my $talk_map = $sink->comment_map;
    $log->( 'Loaded comment map with %d entries.', scalar( keys %$talk_map ) );
    my $threads = DW::Importer::Threading->new(
        entries => \%jitemid_map,
        known =>
            index_comments( $talk_map, $data->{hostname}, $data->{username}, $data->{usejournal} ),
    );

    # for large imports, the maps are big (they contain keys), so let's drop them
    # since we're never going to use them again.
    undef $talk_map;
    undef $entries;
    undef $xpost_map;

    # who the commenters are here, by their name on the remote site
    my %local_poster;

    # hit up the server for metadata
    my $meta = $source->comment_meta(
        log           => $log,
        before_window => sub {

            # let them know we're still working
            $job->grabbed_until( time() + 3600 );
            $job->save;
            $title->( 'meta-fetch from id %d', $_[0] );
        },
        after_window => sub {
            my ( $server_max_id, $usermap ) = @_;

            my @fail_errors;
            foreach my $pair (@$usermap) {
                my ( $id, $user ) = @$pair;

                my ( $local_oid, $local_fid ) = $class->get_remapped_userids( $ctx, $user, $log );

# we want to fail if we weren't able to create a local user, because this would otherwise be mistakenly posted as anonymous
                push @fail_errors,
                    "Unable to map comment poster from $data->{hostname} user '$user' to local user"
                    unless $local_oid;

                $local_poster{$user} = $local_oid;
                $log->( 'Mapped remote %s(%d) to local userid %d.', $user, $id, $local_oid )
                    if $local_oid;
            }
            die $ctx->temp_fail( join( "\n", map { " * $_" } @fail_errors ) )
                if @fail_errors;

            # this is the best place to test for too many comments. if this site is limiting
            # the comment imports for some reason or another, we can bail here.
            die $ctx->fail( $LJ::COMMENT_IMPORT_ERROR || 'Too many comments to import.' )
                if defined $LJ::COMMENT_IMPORT_MAX
                && defined $server_max_id
                && $server_max_id > $LJ::COMMENT_IMPORT_MAX;
        },
    );

    # this is called with comments that have been read. it writes what it can, parents first;
    # if it can't write one it dies with a failure outcome.
    my ( $unmapped, $server_max_id ) = ( 0, $meta->{max_id} );
    my $post_comments = sub {
        my (@comments) = @_;
        $log->( 'post sub starting with %d comments', scalar @comments );

        foreach my $comment (@comments) {

            # remap content (user links) then remove embeds/templates
            my ( $body, @warnings ) = comment_text( $comment->{body}, $data->{hostname} );
            $log->( 'Remote comment %d: %s', $comment->{remote_id}, $_ ) foreach @warnings;

            # now let's do some encoding, just in case the input we get is in some other
            # character encoding
            $comment->{body} = encode_utf8( $body || '' );
            $comment->{subject} = encode_utf8( $comment->{subject} || '' );
            foreach my $prop ( keys %{ $comment->{props} } ) {
                $comment->{props}->{$prop} = encode_utf8( $comment->{props}->{$prop} );
            }

            # where this comment comes from, and who here wrote it
            $comment->{source} = $data->{hostname} if $comment->{external};
            $comment->{posterid} =
                defined $comment->{poster} ? ( $local_poster{ $comment->{poster} } || 0 ) : 0;
        }

        # let's do some batch loads of the users and entries we're going to need
        my ( %jitemids, %userids );
        foreach my $comment (@comments) {
            my $local_entry = $jitemid_map{ $comment->{entry_id} };
            $jitemids{$local_entry} = 1 if $local_entry;
            $userids{ $comment->{posterid} } = 1 if $comment->{posterid};
        }
        $sink->precache( [ keys %jitemids ], [ keys %userids ] );

        foreach my $comment (@comments) {
            my ( $what, $local_id ) = $threads->add($comment);

            if ( $what eq 'unmapped_entry' ) {

                # a new comment whose entry was never imported has nowhere to go; posting it
                # would create a comment attached to entry 0, so skip it and tell the user
                # at the end.
                $log->(
                    'Skipping remote comment %d: remote entry %d is not imported.',
                    $comment->{remote_id}, $comment->{entry_id}
                );
                $unmapped++;
                $sink->note(
                    unmapped => remote_id => $comment->{remote_id},
                    entry_id => $comment->{entry_id}
                );
            }
            elsif ( $what eq 'existing' ) {

                # if this comment already exists, we might need to update it, however
                $log->(
                    "Attempting to import remote id %d, parentid %d, state %s.",
                    $comment->{remote_id}, $comment->{parent_id}, $comment->{state}
                );
                if ( $comment->{state} ne 'D' ) {
                    $log->('Comment already exists, passing to updater.');

                    my $err = "";
                    $sink->update_comment(
                        {
                            %$comment,
                            id       => $local_id,
                            parentid => ( $threads->local_id( $comment->{parent_id} ) || 0 ),
                        },
                        \$err
                    );
                    $log->( 'ERROR: %s', $err ) if $err;
                }
                else {
                    $log->('Comment exists but is deleted, skipping.');
                }
                $sink->note(
                    skip   => type => 'comment',
                    target => $comment->{remote_id},
                    reason => 'already imported'
                );
            }
        }

        $threads->process(
            sub {
                my ( $comment, $local_parent, $local_entry ) = @_;

                # status output update
                $title->( 'posting %d/%d comments', $comment->{remote_id}, $server_max_id );
                $log->(
                    "Attempting to import remote id %d, parentid %d, state %s.",
                    $comment->{remote_id}, $comment->{parent_id}, $comment->{state}
                );
                $log->(
                    'Remote parent %d is local parent %d for orig_id=%d.',
                    $comment->{parent_id}, $local_parent, $comment->{remote_id}
                ) if $comment->{parent_id};

                # if we get here we're good to insert into the database
                my $err    = "";
                my $talkid = $sink->insert_comment(
                    {
                        %$comment,
                        orig_id      => $comment->{remote_id},
                        jitemid      => $local_entry,
                        parentid     => $local_parent,
                        entry_source => $entry_source{$local_entry},
                    },
                    \$err
                );
                unless ($talkid) {
                    $log->( 'Failed to import comment %d: %s.', $comment->{remote_id}, $err );
                    die $ctx->temp_fail( 'Failure importing comment: %s.', $err );
                }

                $log->(
                    'Successfully imported remote id %d to new jtalkid %d.',
                    $comment->{remote_id}, $talkid
                );

                # free up some memory
                delete @{$comment}{qw( props body subject )};
                return $talkid;
            }
        );
        $log->( 'end of post sub has %d comments waiting', scalar( () = $threads->orphans ) );
    };

    # body handling section now
    $source->comment_bodies(
        log           => $log,
        max_id        => $meta->{max_id},
        comments      => $meta->{comments},
        usermap       => $meta->{usermap},
        before_window => sub {

            # let them know we're still working
            $job->grabbed_until( time() + 3600 );
            $job->save;
            $title->( 'body-fetch from id %d', $_[0] );
        },
        window => $post_comments,
    );

    # replies whose parent was never imported can't be placed
    my @orphans = $threads->orphans;
    $log->(
        'ERROR: Failed to map remote parent %d of comment %d.',
        $_->{parent_id}, $_->{remote_id}
    ) foreach @orphans;
    $sink->note( orphan => remote_id => $_->{remote_id}, parent_id => $_->{parent_id} )
        foreach @orphans;

    my @notes;
    push @notes,
        sprintf(
        '%d comments were not imported because the entries they belong to are not imported.',
        $unmapped )
        if $unmapped;
    push @notes,
        sprintf(
        '%d comments were not imported because the comments they reply to are not imported.',
        scalar @orphans )
        if @orphans;
    $ctx->status( text => join( "\n\n", @notes ) ) if @notes;

    # Kick off an indexing job for this user
    $sink->dispatch_search_copy('importcm');

    return $ctx->ok;
}

1;
