#!/usr/bin/perl
#
# DW::Task::EmbedWorker
#
# SQS worker for getting information about embedded media content.
#
# Authors:
#     Deborah Kaplan <deborah@dreamwidth.org>
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2013-2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Task::EmbedWorker;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use LJ::EmbedModule;

use base 'DW::Task';

sub work {
    my ( $self, $handle ) = @_;

    my $arg = { %{ $self->args->[0] } };

    my ( $vid_id, $host, $contents, $preview, $journalid, $id, $cmptext, $linktext, $url ) =
        map { delete $arg->{$_} }
        qw( vid_id host contents preview journalid id cmptext linktext url );

    if ( keys %$arg ) {
        $log->error( "Unknown keys: " . join( ", ", keys %$arg ) );
        return DW::Task::COMPLETED;
    }
    unless ( defined $contents && defined $journalid ) {
        $log->error("Missing argument");
        return DW::Task::COMPLETED;
    }

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
        $log->error("Unknown failure contacting external site");
        return DW::Task::COMPLETED;
    }
    elsif ( $result eq 'warn' ) {
        $log->warn("Did not reach remote site, retrying.");
        return DW::Task::FAILED;
    }

    return DW::Task::COMPLETED;
}

1;
