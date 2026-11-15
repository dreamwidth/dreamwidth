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

use Storable qw/ nfreeze /;
use DW::Worker::ContentImporter::Local::TrustGroups;

sub run {
    my ( $class, $ctx ) = @_;
    my ( $u, $data ) = ( $ctx->u, $ctx->data );

    my $dbh = LJ::get_db_writer()
        or return $ctx->temp_fail('Unable to get global master database handle');

    my @groups = $class->source_for($ctx)->trust_groups;
    my $map = DW::Worker::ContentImporter::Local::TrustGroups->merge_trust_groups( $u, \@groups );

    # store the merged map; the friends and entries jobs read it
    $dbh->do(
        q{UPDATE import_data SET groupmap = ?
          WHERE userid = ? AND import_data_id = ?},
        undef, nfreeze($map), $u->id, $data->{import_data_id}
    );

    return $ctx->ok;
}

1;
