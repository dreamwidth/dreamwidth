#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal
#
# Importer worker for LiveJournal-based sites friends and trust groups.
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

package DW::Worker::ContentImporter::LiveJournal::Friends;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

sub run {
    my ( $class, $ctx ) = @_;
    my $data = $ctx->data;

    # if this is a usejournal request, we have no friends (it's a comm or something) so
    # bail very early
    return $ctx->ok if $data->{usejournal};

    my ( @friends, @feeds );
    foreach my $friend ( $class->source_for($ctx)->friends ) {

        # if we have no type, or type is identity, allow it
        next if $friend->{type} && $friend->{type} ne 'identity';

        # must be visible
        next if $friend->{status};

        # remap into a local OpenID userid and feed if we can
        my ( $local_oid, $local_fid ) = $class->get_remapped_userids( $ctx, $friend->{username} );

        push @friends,
            {
            userid    => $local_oid,
            groupmask => $class->remap_groupmask( $ctx, $friend->{groupmask} ),
            }
            if $local_oid && $local_oid != $data->{userid};

        # We aren't doing feeds right now / maybe not ever, when we solve the
        # authenticated feed reading problem.  (which we're on track for)
        #        push @feeds, {
        #            fgcolor => $friend->{fgcolor},
        #            bgcolor => $friend->{bgcolor},
        #            userid => $local_fid,
        #        } if $local_fid;
    }

    $ctx->sink->merge_trust( \@friends )
        or return $ctx->temp_fail('Could not save all imported access grants.');

    #    DW::Worker::ContentImporter->merge_watch( $u, $opts, \@feeds );

    return $ctx->ok;
}

1;
