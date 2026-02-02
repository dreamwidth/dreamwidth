#!/usr/bin/perl
#
# app.psgi
#
# Dreamwidth entrypoint for Plack.
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

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use Plack::Builder;

use DW::BML;
use DW::Controller::Journal;
use DW::Request::Plack;
use DW::Routing;

# Initial configuration that happens on server startup goes here, these things don't
# change from request to request, so only put things here that never change
BEGIN {
    # If we're a DEV server, do some configuration
    $LJ::IS_DEV_SERVER = 1 if $ENV{LJ_IS_DEV_SERVER};
    $^W                = 1 if $LJ::IS_DEV_SERVER;

    # Configure S2
    S2::set_domain('LJ');

    # Initialize random
    srand( LJ::urandom_int() );
}

my $app = sub {
    my $r = DW::Request->get;

    # Main request dispatch; this will determine what kind of request we're getting
    # and then pass it to the appropriate handler. In the future, this should just
    # be a call to DW::Routing and let it sort it out with all the controllers and
    # such, but until then, we're having to dispatch between various generations
    # of systems ourselves.
    # If this is the embed module domain, force routing to embedcontent handler
    # regardless of the requested path (matches Apache::LiveJournal::trans behavior)
    my $host = $r->host;
    my $uri =
        ( $LJ::EMBED_MODULE_DOMAIN && $host =~ /$LJ::EMBED_MODULE_DOMAIN$/ )
        ? '/journal/embedcontent'
        : $r->path;
    my $ret = DW::Routing->call( uri => $uri );

    # If routing returned a finalized Plack response (arrayref), e.g. from
    # a controller redirect, return it directly — it already has cookies/headers set.
    return $ret if ref $ret;

    # If routing returned OK (0), default status to 200; otherwise try journals, then BML
    if ( defined $ret && $ret == 0 ) {
        $r->status(200) unless $r->status;
    }
    else {
        # Journal path-based routing: /~user/... and /users/user/...
        unless ( defined $ret ) {
            if ( $uri =~ m!^/(?:~|users/)([\w-]+)(.*)$! ) {
                my ( $journal_user, $journal_path ) = ( $1, $2 || '/' );
                $ret = DW::Controller::Journal->render(
                    user => $journal_user,
                    uri  => $journal_path,
                    args => $r->query_string,
                );
            }
        }

        # If journal routing handled it, finalize
        if ( ref $ret ) {
            return $ret;
        }
        elsif ( defined $ret && $ret == 0 ) {
            $r->status(200) unless $r->status;
        }
        elsif ( defined $ret && $ret > 0 ) {
            $r->status($ret);
        }
        else {
            # Routing didn't handle it — try BML file resolution as fallback
            my ( $redirect_url, $bml_uri, $bml_file ) = DW::BML->resolve_path($uri);
            if ($redirect_url) {
                return $r->redirect($redirect_url);
            }
            elsif ($bml_file) {
                DW::BML->render( $bml_file, $bml_uri );
            }
            else {
                $r->status(404) unless $r->status;
            }
        }
    }

    return $r->res;
};

# Apply the middleware. Ordering is important!
builder {
    # Handle OPTIONs requests and otherwise only allow the methods that we expect
    # to be allowed; this will abort any calls that are methods that not accepted
    enable 'Options', allowed => [qw /DELETE GET HEAD POST PUT/];

    # Manages start/end request and things we might want to do around the entire
    # request lifecycle such as logging, resource checking, etc
    enable 'DW::RequestWrapper';

    # Middleware for doing domain redirect management, i.e., we want to ensure that the
    # user has ended up on the right domain (www.dreamwidth.org instead of dreamwidth.co.uk
    # and the like), is also responsible for managing redirect.dat etc
    enable 'DW::Redirects';

    # Handle functional subdomains (shop.dw.org, support.dw.org, etc) by redirecting
    # or rewriting URIs to match Apache::LiveJournal::trans behavior
    enable 'DW::SubdomainFunction';

    if ($LJ::IS_DEV_SERVER) {
        enable 'DW::Dev';
    }

    # Ensure that we get the real user's IP address instead of a proxy
    enable 'DW::XForwardedFor';

    # Concatenated static resources (CSS/JS combo handler)
    enable 'DW::ConcatRes';

    # Plain static file serving from all htdocs directories (main + extensions like
    # dw-nonfree). Ordered by scope priority so extension files override base files.
    # pass_through lets each layer fall through to the next if the file isn't found.
    for my $dir ( LJ::get_all_directories('htdocs') ) {
        enable 'Static',
            path         => qr{^/(img|stc|js)/},
            root         => $dir,
            pass_through => 1;
    }

    # Middleware for ensuring we have the Unique Cookie set up
    enable 'DW::UniqCookie';

    # Middleware for doing user authentication (get remote, dev server ?as= support)
    enable 'DW::Auth';

    # Middleware for doing sysban blocking (IP bans, uniq bans, tempbans, noanon_ip)
    enable 'DW::Sysban';

    $app;
};
