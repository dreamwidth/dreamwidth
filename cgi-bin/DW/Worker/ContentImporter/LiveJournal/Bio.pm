#!/usr/bin/perl
#
# DW::Worker::ContentImporter::LiveJournal::Bio
#
# Importer worker for LiveJournal-based sites bios.
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

package DW::Worker::ContentImporter::LiveJournal::Bio;
use strict;
use base 'DW::Worker::ContentImporter::LiveJournal';

use DW::Importer::Transform::LJMarkup qw( remap_user_tags );
use DW::Worker::ContentImporter::Local::Bio;

sub run {
    my ( $class, $ctx ) = @_;
    my ( $u, $data ) = ( $ctx->u, $ctx->data );

    my $bio = $class->source_for($ctx)->bio;
    unless ($bio) {
        ( my $un = $data->{usejournal} || $data->{username} ) =~ s/_/-/g;
        return $ctx->temp_fail("Unable to load FOAF data for $un.$data->{hostname}.");
    }

    DW::Worker::ContentImporter::Local::Bio->merge_interests( $u, $bio->{interests} );

    $bio->{bio} = remap_user_tags( $bio->{bio}, $data->{hostname} );
    DW::Worker::ContentImporter::Local::Bio->merge_bio_items( $u, $bio );

    return $ctx->ok;
}

1;
