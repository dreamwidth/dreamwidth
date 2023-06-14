#!/usr/bin/perl
#
# Plack::Middleware::DW::XForwardedFor
#
# Sets up IP address based on proxy trust.
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

package Plack::Middleware::DW::XForwardedFor;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use parent qw/ Plack::Middleware /;

sub call {
    my ( $self, $env ) = @_;

    return $self->app->($env)
        unless $LJ::TRUST_X_HEADERS;

    my $r = DW::Request->get;

    # Assume user's IP comes in the real IP, but if not, we need to grab it out of
    # the X-Forwarded-For -- respecting IS_TRUSTED_PROXY
    if ( my $forward = $r->header_in('X-Forwarded-For') ) {
        my @hosts = split( /\s*,\s*/, $forward );
        if (@hosts) {
            my $real;
            if ( ref $LJ::IS_TRUSTED_PROXY eq 'CODE' ) {

                # Find last IP in X-Forwarded-For that isn't a trusted proxy.
                do {
                    $real = pop @hosts;
                } while ( @hosts && $LJ::IS_TRUSTED_PROXY->($real) );
            }
            else {
                # Trust everything by default, real client IP is first.
                $real  = shift @hosts;
                @hosts = ();
            }
            $r->address($real);
        }
        $r->header_in( 'X-Forwarded-For' => join( ", ", @hosts ) );
    }

    # and now, deal with getting the right Host header
    my $host = $r->header_in('X-Host') // $r->header_in('X-Forwarded-Host');
    $r->header_in( 'Host' => $host ) if defined $host;

    return $self->app->($env);
}

1;
