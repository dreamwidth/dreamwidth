#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal::FriendGroups
#
# Importer worker for LiveJournal-based sites friend groups.
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

package DW::Worker::ContentImporter::LiveJournal::FriendGroups;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

sub run {
    my ( $class, $ctx ) = @_;
    my $sink = $ctx->sink;

    my @groups = $class->source_for($ctx)->trust_groups;
    my $map    = $sink->merge_trust_groups( \@groups );

    # store the merged map; the friends and entries jobs read it
    $sink->save_groupmap($map);

    return $ctx->ok;
}

1;
