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

use DW::Worker::ContentImporter::Local::Bio;

sub run {
    my ( $class, $ctx ) = @_;
    my ( $u, $data ) = ( $ctx->u, $ctx->data );

    # FIXME: have to flip this back to using the user_path value instead of hardcoded
    # livejournal.com ... this should probably be part of the import_data structure?
    # abstract out sites?
    my $un = $data->{usejournal} || $data->{username};
    $un =~ s/_/-/g;    # URLs use hyphens, not underscores
    my ( $items, $interests, $schools ) = $class->get_foaf_from("http://$un.$data->{hostname}");
    return $ctx->temp_fail("Unable to load FOAF data for $un.$data->{hostname}.")
        unless $items;

    DW::Worker::ContentImporter::Local::Bio->merge_interests( $u, $interests );

    $items->{bio} = $class->remap_lj_user( $data, $items->{bio} );
    DW::Worker::ContentImporter::Local::Bio->merge_bio_items( $u, $items );

    return $ctx->ok;
}

1;
