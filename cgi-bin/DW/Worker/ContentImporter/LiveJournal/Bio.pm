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

use Carp qw/ croak confess /;
use DW::Worker::ContentImporter::Local::Bio;

sub work {

    # VITALLY IMPORTANT THAT THIS IS CLEARED BETWEEN JOBS
    %DW::Worker::ContentImporter::LiveJournal::MAPS = ();

    my ( $class, $job ) = @_;
    my $opts = $job->arg;
    my $data = $class->import_data( $opts->{userid}, $opts->{import_data_id} );

    return $class->decline($job) unless $class->enabled($data);

    eval { try_work( $class, $job, $opts, $data ); };
    if ( my $msg = $@ ) {
        $msg =~ s/\r?\n/ /gs;
        return $class->temp_fail( $data, 'lj_bio', $job, 'Failure running job: %s', $msg );
    }
}

sub try_work {
    my ( $class, $job, $opts, $data ) = @_;

    # failure wrappers for convenience
    my $fail      = sub { return $class->fail( $data, 'lj_bio', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_bio', $job ); };
    my $temp_fail = sub { return $class->temp_fail( $data, 'lj_bio', $job, @_ ); };

    # setup
    my $u = LJ::load_userid( $data->{userid} )
        or return $fail->( 'Unable to load target with id %d.', $data->{userid} );

    $0 = sprintf( 'content-importer [bio: %s(%d)]', $u->user, $u->id );

    my $ua = LJ::get_useragent(
        role     => 'importer',
        max_size => 524288,       # half meg, this should be plenty
        timeout  => 20,           # 20 seconds, might need tuning for slow sites
    ) or return $temp_fail->('Unable to allocate useragent.');

    # FIXME: have to flip this back to using the user_path value instead of hardcoded
    # livejournal.com ... this should probably be part of the import_data structure?
    # abstract out sites?
    my $un = $data->{usejournal} || $data->{username};
    $un =~ s/_/-/g;    # URLs use hyphens, not underscores
    my ( $items, $interests, $schools ) =
        $class->get_foaf_from("http://$un.$data->{hostname}/data/foaf");
    return $temp_fail->("Unable to load FOAF data for $un.$data->{hostname}.")
        unless $items;

    DW::Worker::ContentImporter::Local::Bio->merge_interests( $u, $interests );

    $items->{bio} = $class->remap_lj_user( $data, $items->{bio} );
    DW::Worker::ContentImporter::Local::Bio->merge_bio_items( $u, $items );

    return $ok->();
}

1;
