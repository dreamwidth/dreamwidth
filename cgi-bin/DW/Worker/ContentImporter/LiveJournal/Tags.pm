#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal::Tags
#
# Importer worker for LiveJournal-based sites tags.
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

package DW::Worker::ContentImporter::LiveJournal::Tags;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

use DW::Worker::ContentImporter::Local::Tags;

sub run {
    my ( $class, $ctx ) = @_;

    my @tags = $class->source_for($ctx)->tags;
    DW::Worker::ContentImporter::Local::Tags->merge_tags( $ctx->u, \@tags );

    return $ctx->ok;
}

1;
