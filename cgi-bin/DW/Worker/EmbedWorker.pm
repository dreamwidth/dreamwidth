#!/usr/bin/perl
#
# DW::Worker::EmbedWorker
#
# TheSchwartz worker module for getting information about
# embedded media content. Called with:
# LJ::theschwartz()->insert('DW::Worker::EmbedWorker', {
# ?? });
#
# Authors:
#      Deborah Kaplan <deborah@dreamwidth.org>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

package DW::Worker::EmbedWorker;
use base 'TheSchwartz::Worker';

sub schwartz_capabilities { return ('DW::Worker::EmbedWorker'); }

# Retry nine times. Final back off times are lengthy (half a day,
# a day) in case the remote site is having problems.
sub max_retries { 9 }

sub retry_delay {
    my ( $class, $fails ) = @_;

    return ( 10, 30, 60, 300, 600, 1200, 2400, 43200, 86400 )[$fails];
}
sub grab_for             { 600 }      # Give the stable hand 600 seconds (10 minutes) to finish
sub keep_exit_status_for { 86400 }    # Keep the result of the feeding attempt for 24 hours

# Attempts to contact the embed hosting API for more information, sets memcache and db
# currently handles: YouTube, Vimeo
sub work {
    my ( $class, $job ) = @_;

    my $arg = { %{ $job->arg } };

    my ( $vid_id, $host, $contents, $preview, $journalid, $id, $cmptext, $linktext, $url ) =
        map { delete $arg->{$_} }
        qw( vid_id host contents preview journalid id cmptext linktext url );

    return $job->permanent_failure( "Unknown keys: " . join( ", ", keys %$arg ) )
        if keys %$arg;
    return $job->permanent_failure("Missing argument")
        unless defined $contents && defined $journalid;

    my $result = LJ::EmbedModule->contact_external_sites(
        {
            vid_id    => $vid_id,
            host      => $host,
            preview   => $preview,
            contents  => $contents,
            cmptext   => $cmptext,
            journalid => $journalid,
            id        => $id,
            linktext  => $linktext,
            url       => $url,
        }
    );
    if ( $result eq 'fail' ) {
        return $job->permanent_failure("Unknown failure");
    }
    elsif ( $result eq 'warn' ) {
        return $job->failed("Did not reach remote site, retrying.");
    }
    $job->completed;
}

1;
