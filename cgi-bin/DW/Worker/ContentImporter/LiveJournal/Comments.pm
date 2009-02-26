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
use DW::Worker::ContentImporter::Local::Comments;

# these come from LJ
our $COMMENTS_FETCH_META = 10000;
our $COMMENTS_FETCH_BODY = 1000;

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
    my $fail      = sub { return $class->fail( $data, 'lj_comments', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_comments', $job ); };
    my $temp_fail = sub { return $class->temp_fail( $data, 'lj_comments', $job, @_ ); };

    # setup
    my $u = LJ::load_userid( $data->{userid} )
        or return $fail->( 'Unable to load target with id %d.', $data->{userid} );

    # temporary failure, this code hasn't been ported yet
    return $fail->( 'oops, not ready yet' );
}

1;
__END__

### WORK GOES HERE
$opts->{identity_map} ||= {};

# this will take a entry_map (old URL -> new jitemid) and convert it into a jitemid map (old jitemid -> new jitemid)
# TODO: Make sure you are dealing with the correct site.
unless ( $opts->{jitemid_map} ) {
    $opts->{entry_map} ||= DW::Worker::ContentImporter->get_entry_map($u,$opts);
    $opts->{jitemid_map} = {};
    foreach my $url ( keys %{$opts->{entry_map}} ) {
        next unless $url =~ m/$opts->{user_path}/;
        my ($ditemid) = $url =~ m/\/([0-9]+)\.html?$/;
        my $jitemid = $ditemid >> 8;
        $opts->{jitemid_map}->{$jitemid} = $opts->{entry_map}->{$url};
    }
}

# this will take a talk_map (old URL -> new jtalkid) and convert it to a jtalkid map (old jtalkid -> new jtalkid)
# TODO: Make sure you are dealing with the correct site.
unless ( $opts->{jtalkid_map} ) {
    $opts->{talk_map} ||= DW::Worker::ContentImporter->get_comment_map( $u, $opts );
    $opts->{jtalkid_map} = {};
    foreach my $url ( keys %{$opts->{talk_map}} ) {
        next unless $url =~ m/$opts->{user_path}/;
        my ( $dtalkid ) = $url =~ m/\?thread=([0-9]+)$/;
        my $jtalkid = $dtalkid >> 8;
        $opts->{jtalkid_map}->{$jtalkid} = $opts->{talk_map}->{$url};
    }
}

# downloaded meta data information
my %meta;
my @userids;

# setup our parsing function
my $maxid = 0;
my $server_max_id = 0;
my $server_next_id = 1;
my $lasttag = '';
my $meta_handler = sub {
    # this sub actually processes incoming meta information
    $lasttag = $_[1];
    shift; shift;      # remove the Expat object and tag name
    my %temp = ( @_ ); # take the rest into our humble hash
    if ( $lasttag eq 'comment' ) {
        # get some data on a comment
        $meta{$temp{id}} = {
            id => $temp{id},
            posterid => $temp{posterid}+0,
            state => $temp{state} || 'A',
        };
    } elsif ( $lasttag eq 'usermap' && !$opts->{identity_map}->{$temp{id}} ) {
        push @userids, $temp{id};
        $opts->{identity_map}->{$temp{id}} = remap_username_friend( $opts, $temp{user} );
    }
};
my $meta_closer = sub {
    # we hit a closing tag so we're not in a tag anymore
    $lasttag = '';
};
my $meta_content = sub {
    # if we're in a maxid tag, we want to save that value so we know how much further
    # we have to go in downloading meta info
    return unless ( $lasttag eq 'maxid' ) || ( $lasttag eq 'nextid' );
    $server_max_id = $_[1] + 0 if ( $lasttag eq 'maxid' );
    $server_next_id = $_[1] + 0 if ( $lasttag eq 'nextid' );
};

# hit up the server for metadata
while ( defined $server_next_id && $server_next_id =~ /^\d+$/ ) {
    DW::Worker::ContentImporter->ratelimit_request( $opts );
    my $content = do_authed_fetch( $opts, 'comment_meta', $server_next_id, $COMMENTS_FETCH_META, $session );
    #die "Some sort of error fetching metadata from server" unless $content;

    $server_next_id = undef;

    # now we want to XML parse this
    my $parser = new XML::Parser( Handlers => { Start => $meta_handler, Char => $meta_content, End => $meta_closer } );
    $parser->parse( $content );
}

# setup our handlers for body XML info
my $lastid = 0;
my $curid = 0;
my @tags;
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
        # line below commented out because we shouldn't be trying to be clever like this ;p
        # $lastid = $curid if $curid > $lastid;
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

# at this point we have a fully regenerated metadata cache and we want to grab a block of comments
while ( 1 ) {
    DW::Worker::ContentImporter->ratelimit_request( $opts );
    my $content = do_authed_fetch( $opts, 'comment_body', $lastid+1, $COMMENTS_FETCH_BODY, $session );

    # now we want to XML parse this
    my $parser = new XML::Parser( Handlers => { Start => $body_handler, Char => $body_content, End => $body_closer } );
    $parser->parse( $content );

    # now at this point what we have to decide whether we should loop again for more metadata
    $lastid += $COMMENTS_FETCH_BODY;
    last unless $lastid < $server_max_id;
}

foreach my $comment ( values %meta ) {
    $comment->{posterid} = $opts->{identity_map}->{$comment->{posterid}};
    $comment->{jitemid} = $opts->{jitemid_map}->{$comment->{jitemid}};

    $comment->{unresolved} = 1 if ($comment->{parentid});

    my $body = remap_lj_user($opts,$comment->{body});
    $body =~ s/<.+?-embed-.+?>//g;
    $body =~ s/<.+?-template-.+?>//g;
    $comment->{body} = $body;

    $comment->{orig_id} = $comment->{id};

    if ($comment->{parentid} && $comment->{state} ne 'D') {
        $meta{$comment->{parentid}}->{has_children} = 1;
    }
}

my @to_import = sort { ( $a->{id}+0 ) <=> ( $b->{id}+0 ) } values %meta;
my $had_unresolved = 1;
# This loop should never need to run through more then once
# but, it will *if* for some reason a comment comes before its parent
# which *should* never happen, but I'm handling it anyway, just in case.
while ($had_unresolved) {
    $had_unresolved = 0;
    my $ct = 0;
    my $ct_unresolved = 0;
    foreach my $comment (@to_import) {
        next if $comment->{done}; # Skip this comment if it was already imported this round
        next if $opts->{jtalkid_map}->{$comment->{orig_id}}; # Or on a previous import round
        next if ( $comment->{state} eq 'D' && !$comment->{has_children} ); # Or if the comment is deleted, and child-less
        $ct++;
        if ( $comment->{unresolved} ) {
            # lets see if this is resolvable at the moment
            # A resolvable comment is a comment that's parent is already in the DW database
            # and an unresolved comment is a comment that has a parent that is currently not in the database.
            if ( $opts->{jtalkid_map}->{$comment->{parentid}} ) {
                $comment->{parentid} = $opts->{jtalkid_map}->{$comment->{parentid}};
                $comment->{unresolved} = 0;
            }
        }
        if ( $comment->{unresolved} ) {
            $ct_unresolved++;
            $had_unresolved = 1;
            next;
        }
        my $talkid = DW::Worker::ContentImporter->insert_comment( $u, $opts, $comment );
        $opts->{jtalkid_map}->{$comment->{id}} = $talkid;
        $comment->{id} = $talkid;
        $comment->{done} = 1;
    }
    # Sanity check. This *really* should never happen.
    # This is here to prevent an endless loop, just in case.
    # The only way I can see this firing is if a comment is just
    # totally missing.
    if ( $ct == $ct_unresolved && $had_unresolved ) {
        # FIXME: Error
        $had_unresolved = 0; # Set this to 0 so the loop falls through
    }
}
$opts->{no_comments} = 1;

    return $ok->();
}


1;