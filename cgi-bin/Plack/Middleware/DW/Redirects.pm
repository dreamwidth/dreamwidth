#!/usr/bin/perl
#
# Plack::Middleware::DW::Redirects
#
# Handles basic redirects if the user is hitting a non-canonical domain or if
# they're hitting something in redirect.dat etc.
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

package Plack::Middleware::DW::Redirects;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use parent qw/ Plack::Middleware /;

use Carp qw/ confess /;
use URI;

use DW::Request;

sub call {
    my ( $self, $env ) = @_;

    my $r    = DW::Request->get;
    my $host = $r->host;
    my $path = $r->path;
    my $args = $r->query_parameters;

    # Handle base domain -> web domain (matches Apache::LiveJournal::trans)
    if (   $LJ::DOMAIN_WEB
        && $r->method eq "GET"
        && $host eq $LJ::DOMAIN
        && $LJ::DOMAIN_WEB ne $LJ::DOMAIN )
    {
        my $uri = URI->new("$LJ::SITEROOT$path");
        $uri->query_form(%$args) if $args;
        return $r->redirect( $uri->as_string );
    }

    # handle alternate domains
    if (   $host ne $LJ::DOMAIN
        && $host ne $LJ::DOMAIN_WEB
        && !( $LJ::EMBED_MODULE_DOMAIN && $host =~ /$LJ::EMBED_MODULE_DOMAIN$/ ) )
    {
        my $which_alternate_domain = undef;
        foreach my $other_host (@LJ::ALTERNATE_DOMAINS) {
            $which_alternate_domain = $other_host
                if $host =~ m/\Q$other_host\E$/i;
        }

        if ( defined $which_alternate_domain ) {
            my $root = "$LJ::PROTOCOL://";
            $host =~ s/\Q$which_alternate_domain\E$/$LJ::DOMAIN/i;

            # do $LJ::DOMAIN -> $LJ::DOMAIN_WEB here, to save a redirect.
            if ( $LJ::DOMAIN_WEB && $host eq $LJ::DOMAIN ) {
                $host = $LJ::DOMAIN_WEB;
            }
            $root .= "$host";

            if ( $r->method eq "GET" ) {
                my $uri = URI->new("$root$path");
                $uri->query_form(%$args) if $args;
                return $r->redirect( $uri->as_string );
            }
            else {
                # Simpler redirect, we're dropping arguments and such here
                return $r->redirect($root);
            }
        }
    }

    # Static redirects from redirect.dat (301 Moved Permanently, matching Apache behavior)
    my $redir = _load_redirects();
    if ( my $dest = $redir->{$path} ) {
        if ( $env->{QUERY_STRING} && length $env->{QUERY_STRING} ) {
            $dest .= ( $dest =~ /\?/ ? '&' : '?' ) . $env->{QUERY_STRING};
        }
        return [ 301, [ 'Location' => $dest, 'Content-Type' => 'text/html' ], [''] ];
    }

    return $self->app->($env);
}

my $_redirects;

sub _load_redirects {
    return $_redirects if $_redirects;

    my %redir;
    foreach my $file ( 'redirect.dat', 'redirect-local.dat' ) {
        open my $fh, '<', "$LJ::HOME/cgi-bin/$file"
            or next;
        while (<$fh>) {
            next unless /^(\S+)\s+(\S+)/;
            $redir{$1} = $2;
        }
        close $fh;
    }

    $_redirects = \%redir;
    return $_redirects;
}

1;
