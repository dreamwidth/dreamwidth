#!/usr/bin/perl
#
# Plack::Middleware::DW::UniqCookie
#
# Ensures the unique tracking cookie is set for every request.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package Plack::Middleware::DW::UniqCookie;

use strict;
use v5.10;

use parent qw/ Plack::Middleware /;

use LJ::UniqCookie;

sub call {
    my ( $self, $env ) = @_;

    LJ::UniqCookie->ensure_cookie_value;

    return $self->app->($env);
}

1;
