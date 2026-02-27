#!/usr/bin/perl
#
# Plack::Middleware::DW::SubdomainFunction
#
# Handles subdomain-based routing that matches the Apache::LiveJournal::trans
# behavior for functional subdomains (shop, support, mobile, cssproxy) and
# user journal subdomains (username.dreamwidth.org).
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
use LJ::Session;

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
        return $r->redirect( "$LJ::PROTOCOL://$2.$LJ::USER_DOMAIN" . $r->path )
            if $1 && $1 eq 'www.';

        my $user = $2;

        # Handle __setdomsess on any subdomain — sets the domain session cookie
        # and redirects to the destination. Matches Apache::LiveJournal::trans
        # behavior for shop (line 959) and journal subdomains (line 704).
        if ( $r->path eq '/__setdomsess' ) {
            return $r->redirect( LJ::Session->setdomsess_handler );
        }

        my $func = $LJ::SUBDOMAIN_FUNCTION{$user};

        # "normal" means treat as www (ignore subdomain)
        if ( $func && $func eq 'normal' ) {

            # fall through to app

        }
        elsif ( $func && $func eq 'cssproxy' ) {
            $env->{PATH_INFO} = '/extcss';
            return $self->app->($env);

        }
        elsif ( $func && $func eq 'shop' ) {
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
        elsif ( $func && ref $func eq 'ARRAY' && $func->[0] eq 'changehost' ) {
            my $args = $env->{QUERY_STRING};
            my $dest = "$LJ::PROTOCOL://$func->[1]" . $r->path;
            $dest .= "?$args" if $args && length $args;
            return $r->redirect($dest);

        }
        elsif ( $func && $func eq 'userpics' ) {

            # Userpic subdomain (e.g., v.dreamwidth.org): URLs are /{picid}/{userid}.
            # Rewrite to /userpic/{picid}/{userid} to match DW::Controller::Userpic's
            # route. Skip domain session bounce since userpics are public images that
            # don't need authentication. (Apache::LiveJournal::trans line 982)
            $env->{PATH_INFO}               = "/userpic" . $r->path;
            $env->{'dw.skip_domain_bounce'} = 1;

        }
        elsif ( $func && $func eq 'journal' ) {

            # "journal" function: URI contains /username/path
            my $uri = $r->path;
            if ( $uri =~ m!^/(\w{1,25})(/.*)?$! ) {
                $env->{'dw.journal_user'} = $1;
                $env->{'dw.journal_path'} = $2 || '/';
            }

            # else: not a valid journal path, let it fall through (will 404)

        }
        elsif ( !$func ) {

            # No SUBDOMAIN_FUNCTION entry: treat subdomain as username
            if ( $user eq 'shop' ) {

                # Legacy shop subdomain without config: rewrite URI
                my $path = $r->path;
                $path =~ s/\/$//;
                $env->{PATH_INFO} = "/shop$path";
            }
            else {
                # User journal subdomain (username.dreamwidth.org)
                $env->{'dw.journal_user'} = $user;
                $env->{'dw.journal_path'} = $r->path || '/';
            }
        }

        # else: unknown $func, fall through
    }

    return $self->app->($env);
}

1;
