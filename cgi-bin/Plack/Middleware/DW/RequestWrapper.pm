#!/usr/bin/perl
#
# Plack::Middleware::DW::RequestWrapper
#
# Sets up the DW::Request::Plack and also handles start/stop request logic that
# needs to wrap every request.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2021 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package Plack::Middleware::DW::RequestWrapper;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use parent qw/ Plack::Middleware /;

use DW::Request;

sub call {
    my ( $self, $env ) = @_;

    # Request setup -- TODO: all this per-request caching that happens in the LJ namespace
    # should really be excised and moved into the DW::Request object
    LJ::start_request();
    LJ::Procnotify::check();

    # Standardize into a DW::Request module
    my $r = DW::Request->get( plack_env => $env );

    # Pass on down
    $log->debug('Request wrapped.');
    my $res = $self->app->($env);
    $log->debug('Request complete.');

    # Close out and return
    LJ::end_request();
    return $res;
}

1;
