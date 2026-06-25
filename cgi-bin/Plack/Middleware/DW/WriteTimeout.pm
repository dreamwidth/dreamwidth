#!/usr/bin/perl
#
# Plack::Middleware::DW::WriteTimeout
#
# Sets a send timeout on the client socket so that Starman workers don't block
# indefinitely when the downstream peer (e.g. ALB) closes the connection before
# the response is fully written. Without this, workers can be stuck in write()
# for the entire TCP retransmit cycle (13-30 minutes), eventually exhausting
# all available workers.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package Plack::Middleware::DW::WriteTimeout;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use parent qw/ Plack::Middleware /;
use Plack::Util::Accessor qw/ timeout /;

use Socket qw/ SOL_SOCKET SO_SNDTIMEO /;

sub call {
    my ( $self, $env ) = @_;

    my $sock = $env->{'psgix.io'};
    if ($sock) {
        my $secs    = $self->timeout || 30;
        my $timeval = pack( 'l!l!', $secs, 0 );
        setsockopt( $sock, SOL_SOCKET, SO_SNDTIMEO, $timeval )
            or $log->warn("Failed to set SO_SNDTIMEO: $!");
    }

    return $self->app->($env);
}

1;
