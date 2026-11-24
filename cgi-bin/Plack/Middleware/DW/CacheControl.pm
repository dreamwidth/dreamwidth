#!/usr/bin/perl
#
# Plack::Middleware::DW::CacheControl
#
# Marks dynamic responses private so shared caches (CDNs, corporate or ISP
# proxies) never store them, unless the handler chose its own Cache-Control.
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

package Plack::Middleware::DW::CacheControl;

use strict;
use v5.10;

use parent qw/ Plack::Middleware /;

use Plack::Util;

sub call {
    my ( $self, $env ) = @_;

    my $res = $self->app->($env);

    return Plack::Util::response_cb(
        $res,
        sub {
            my $res = shift;

            # Handlers that set their own policy (journal pages, no_cache routes,
            # public userpics) keep it. Caches copy a 304's Cache-Control onto
            # the stored response, so such handlers must send the same policy
            # on their 304s as on their 200s.
            return if Plack::Util::header_exists( $res->[1], 'Cache-Control' );

            push @{ $res->[1] }, 'Cache-Control' => 'private, no-cache';
        }
    );
}

1;
