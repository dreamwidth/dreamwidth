#!/usr/bin/perl
#
# Plack::Middleware::DW::SecurityHeaders
#
# Adds security headers to all responses (matches Apache::LiveJournal::trans).
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

package Plack::Middleware::DW::SecurityHeaders;

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

            push @{ $res->[1] }, 'X-Content-Type-Options' => 'nosniff';
            push @{ $res->[1] }, 'Referrer-Policy'        => 'same-origin';

            if ( $LJ::PROTOCOL eq 'https' ) {
                push @{ $res->[1] },
                    'Strict-Transport-Security' => 'max-age=300; includeSubDomains';
            }
        }
    );
}

1;
