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

use Carp qw/ croak confess /;

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
    my $fail      = sub { return $class->fail( $data, 'lj_friends', $job, @_ ); };
    my $ok        = sub { return $class->ok( $data, 'lj_friends', $job ); };
    my $temp_fail = sub { return $class->temp_fail( $job, @_ ); };

    # setup
    my $u = LJ::load_userid( $data->{userid} )
        or return $fail->( 'Unable to load target with id %d.', $data->{userid} );

    my $r = $class->call_xmlrpc( $data, 'getfriends', { includegroups => 1 } );
    return $temp_fail->( 'XMLRPC failure' )
        if ! $r || $r->{fault};

    my ( @friends, @feeds );
    foreach my $friend (@{ $r->{friends} || [] }) {
        my $local_userid = $class->remap_username_friend( $data, $friend->{username} );
        push @friends, {
            userid => $local_userid,
            groupmask => $class->remap_groupmask( $data, $friend->{groupmask} ),
        } if $local_userid;

        $local_userid = $class->remap_username_feed( $data, $friend->{username} );
        push @feeds, {
            fgcolor => $friend->{fgcolor},
            bgcolor => $friend->{bgcolor},
            userid => $local_userid,
        } if $local_userid;
    }

    DW::Worker::ContentImporter->merge_trust( $u, $opts, \@friends );
    DW::Worker::ContentImporter->merge_watch( $u, $opts, \@feeds );

    return $ok->();
}


1;
