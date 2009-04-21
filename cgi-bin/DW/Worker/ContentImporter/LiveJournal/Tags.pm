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

use Carp qw/ croak confess /;
use DW::Worker::ContentImporter::Local::Tags;

sub work {
    my ( $class, $job ) = @_;
    my $opts = $job->arg;
    my $data = $class->import_data( $opts->{userid}, $opts->{import_data_id} );

    eval { try_work( $class, $job, $opts, $data ); };
    if ( my $msg = $@ ) {
        $msg =~ s/\r?\n/ /gs;
        return $class->temp_fail( $data, 'lj_tags', $job, 'Failure running job: %s', $msg );
    }
}

sub try_work {
    my ( $class, $job, $opts, $data ) = @_;

    # failure wrappers for convenience
    my $fail      = sub { return $class->fail( $data, 'lj_tags', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_tags', $job ); };
    my $temp_fail = sub { return $class->temp_fail( $data, 'lj_tags', $job, @_ ); };

    # setup
    my $u = LJ::load_userid( $data->{userid} )
        or return $fail->( 'Unable to load target with id %d.', $data->{userid} );
    $0 = sprintf( 'content-importer [tags: %s(%d)]', $u->user, $u->id );

    # get tags
    my $r = $class->call_xmlrpc( $data, 'getusertags' );
    return $temp_fail->( 'XMLRPC failure: ' . $r->{faultString} )
        if ! $r || $r->{fault};

    DW::Worker::ContentImporter::Local::Tags->merge_tags( $u, $r->{tags} );

    return $ok->();
}


1;
