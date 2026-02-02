#!/usr/bin/perl
#
# Plack::Middleware::DW::SubdomainFunction
#
# Handles subdomain-based routing that matches the Apache::LiveJournal::trans
# behavior for functional subdomains (shop, support, mobile, etc).
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

package Plack::Middleware::DW::SubdomainFunction;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use parent qw/ Plack::Middleware /;

use DW::Request;

sub call {
    my ( $self, $env ) = @_;

    my $r    = DW::Request->get;
    my $host = $r->host;

    # Extract subdomain: match (subdomain).USER_DOMAIN, skip www
    if (   $LJ::USER_DOMAIN
        && $host =~ /^(www\.)?([\w\-]{1,25})\.\Q$LJ::USER_DOMAIN\E$/
        && $2 ne "www" )
    {
        # www.username.domain → redirect to canonical (drop www prefix)
        return $r->redirect("$LJ::PROTOCOL://$2.$LJ::USER_DOMAIN" . $r->path)
            if $1 && $1 eq 'www.';

        my $user = $2;
        my $func = $LJ::SUBDOMAIN_FUNCTION{$user};

        if ( $func && $func eq 'shop' ) {
            my $uri = $r->path;
            $uri =~ s/\/$//;
            my $args = $env->{QUERY_STRING};
            my $dest = "$LJ::SITEROOT/shop$uri";
            $dest .= "?$args" if $args && length $args;
            return $r->redirect($dest);
        }
        elsif ( $func && $func eq 'support' ) {
            return $r->redirect("$LJ::SITEROOT/support/");
        }
        elsif ( $func && $func eq 'mobile' ) {
            my $uri = $r->path;
            return $r->redirect("$LJ::SITEROOT/mobile$uri");
        }
        elsif ( !$func && $user eq 'shop' ) {
            # No SUBDOMAIN_FUNCTION entry but subdomain is 'shop': rewrite URI
            my $path = $r->path;
            $path =~ s/\/$//;
            $env->{PATH_INFO} = "/shop$path";
        }
    }

    return $self->app->($env);
}

1;
