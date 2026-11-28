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

# Returns a coderef that says whether an IP is a proxy we trust for this
# request, or undef if no proxy trust is configured.
#
# $LJ::IS_TRUSTED_PROXY is always trusted. $LJ::IS_CDN_PROXY (e.g. a CDN's
# edge servers) is trusted only when the request also carries the secret
# $LJ::CDN_PROXY_SECRET in the $LJ::CDN_PROXY_SECRET_HEADER header, which our
# own CDN configuration adds. Other customers of the same CDN can point it at
# us and set any X-Forwarded-For they like, but can't send the secret, so
# their requests are treated as coming from the CDN server itself.
sub trusted_proxy_checker {
    my ($env) = @_;

    my $base = ref $LJ::IS_TRUSTED_PROXY eq 'CODE' ? $LJ::IS_TRUSTED_PROXY : undef;
    my $cdn  = ref $LJ::IS_CDN_PROXY eq 'CODE'     ? $LJ::IS_CDN_PROXY     : undef;

    if ($cdn) {
        my $header = $LJ::CDN_PROXY_SECRET_HEADER || 'X-DW-WAF-Bypass';
        my $key    = 'HTTP_' . uc($header);
        $key =~ tr/-/_/;
        my $sent = $env->{$key};
        my $ok   = $LJ::CDN_PROXY_SECRET && defined $sent && $sent eq $LJ::CDN_PROXY_SECRET;

        # Without the secret, trust only the base proxies. If there are none,
        # trust nothing (the last hop is the client) rather than returning
        # undef, which the caller reads as "trust every hop".
        return $base || sub { 0 }
            unless $ok;
    }

    return $base unless $cdn;
    return $cdn  unless $base;
    return sub { $base->( $_[0] ) || $cdn->( $_[0] ) };
}

sub call {
    my ( $self, $env ) = @_;

    return $self->app->($env)
        unless $LJ::TRUST_X_HEADERS;

    my $r = DW::Request->get;

    # Assume user's IP comes in the real IP, but if not, we need to grab it out of
    # the X-Forwarded-For -- respecting our trusted proxies
    if ( my $forward = $r->header_in('X-Forwarded-For') ) {
        my @hosts = split( /\s*,\s*/, $forward );
        if (@hosts) {
            my $real;
            if ( my $trusted = trusted_proxy_checker($env) ) {

                # Find last IP in X-Forwarded-For that isn't a trusted proxy.
                do {
                    $real = pop @hosts;
                } while ( @hosts && $trusted->($real) );
            }
            else {
                # Trust everything by default, real client IP is first.
                $real  = shift @hosts;
                @hosts = ();
            }
            $r->address($real);

            # Also update the PSGI env so infrastructure that reads it
            # directly (Starman access log, Sysban, etc.) sees the real IP.
            $env->{REMOTE_ADDR} = $real;
        }
        $r->header_in( 'X-Forwarded-For' => join( ", ", @hosts ) );
    }

    # and now, deal with getting the right Host header
    my $host = $r->header_in('X-Host') // $r->header_in('X-Forwarded-Host');
    $r->header_in( 'Host' => $host ) if defined $host;

    return $self->app->($env);
}

1;
