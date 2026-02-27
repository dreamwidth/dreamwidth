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

    # Request setup -- clears caches, reloads config, resets DW::Request
    LJ::start_request();

    # Standardize into a DW::Request module. Must happen after start_request
    # (which calls DW::Request->reset) but before we need the request object.
    my $r = DW::Request->get( plack_env => $env );

    # Register standard CSS/JS resources. Under Apache, start_request handles
    # this because DW::Request is auto-discoverable via Apache2::RequestUtil.
    # Under Plack, the request doesn't exist until we explicitly create it
    # above, so start_request's resource registration was skipped.
    LJ::register_standard_resources();

    # Initialize BML language getter so LJ::Lang::ml / BML::ml work for all pages
    my $lang = $LJ::DEFAULT_LANG || $LJ::LANGS[0];
    BML::set_language( $lang, \&LJ::Lang::get_text );

    # Pass on down
    my $res = $self->app->($env);

    # Close out and return
    LJ::end_request();
    return $res;
}

1;
