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

# Track the worker PID we last seeded the RNG for. With --preload-app the
# srand() in the BEGIN block above runs once in the master, so every forked
# worker would otherwise inherit an identical random sequence. Reseed once per
# worker on its first request. (DW's security-sensitive randomness uses
# /dev/urandom, not rand(); this just keeps rand() well-distributed.)
my $srand_pid = 0;

my $app = sub {
    my $env = $_[0];

    if ( $srand_pid != $$ ) {
        srand( LJ::urandom_int() );
        $srand_pid = $$;
    }

    my $r = DW::Request->get;

    # Run the actual dispatch. A finalized Plack response (arrayref) is returned
    # directly; anything else means the status/body now live on $r.
    my $response = eval { _handle_request( $r, $env ) };
    if ( my $err = $@ ) {

        # In dev, re-throw so the StackTrace middleware can render the trace in
        # the browser. In production, turn it into a 500 and fall through to the
        # error-document handling below — this mirrors mod_perl translating a
        # died handler into a 500 and Apache then serving ErrorDocument 500.
        die $err if $LJ::IS_DEV_SERVER;

        warn "Unhandled request exception: $err";
        $r->status(500);
        $response = undef;
    }

    # A finalized response already carries its own body/headers (e.g. redirects).
    return $response if ref $response;

    # If we settled on an error status but no handler produced a body, render
    # the matching error document so the client gets a real page instead of an
    # empty response (which browsers replace with their own generic error page).
    # Mirrors the ErrorDocument directives Apache::LiveJournal sets up.
    _render_error_document($r) if $r->status >= 400 && !$r->response_bytes_written;

    return $r->res;
};

# Main request dispatch; this will determine what kind of request we're getting
# and then pass it to the appropriate handler. In the future, this should just
# be a call to DW::Routing and let it sort it out with all the controllers and
# such, but until then, we're having to dispatch between various generations
# of systems ourselves.
#
# Returns a finalized Plack response (arrayref) for responses that carry their
# own headers/body (redirects, etc.); otherwise returns undef after setting the
# status (and possibly body) on $r, leaving finalization to the caller.
sub _handle_request {
    my ( $r, $env ) = @_;

    # If this is the embed module domain, force routing to embedcontent handler
    # regardless of the requested path (matches Apache::LiveJournal::trans behavior)
    my $host = $r->host;
    my $uri =
        ( $LJ::EMBED_MODULE_DOMAIN && $host =~ /$LJ::EMBED_MODULE_DOMAIN$/ )
        ? '/journal/embedcontent'
        : $r->path;

    # Handle legacy RPC URIs (/__rpc_delcomment, /__rpc_talkscreen) that
    # Apache routes via LJ::URI->handle() to BML files
    if ( my ($rpc) = $uri =~ m!^.*/__rpc_(\w+)$! ) {
        if ( my $bml_file = $LJ::AJAX_URI_MAP{$rpc} ) {
            DW::BML->render( "$LJ::HTDOCS/$bml_file", $uri );
            return;
        }
    }

    my $ret = DW::Routing->call(
        uri      => $uri,
        username => $env->{'dw.journal_user'},
    );

    # If routing returned a finalized Plack response (arrayref), e.g. from
    # a controller redirect, return it directly — it already has cookies/headers set.
    return $ret if ref $ret;

    # If routing returned OK (0), default status to 200; otherwise try journals, then BML
    if ( defined $ret && $ret == 0 ) {
        $r->status(200) unless $r->status;
    }
    else {
        # Journal routing: subdomain-based (set by SubdomainFunction middleware)
        # or path-based (/~user/... and /users/user/...)
        unless ( defined $ret ) {
            my ( $journal_user, $journal_path );

            if ( $env->{'dw.journal_user'} ) {
                $journal_user = $env->{'dw.journal_user'};
                $journal_path = $env->{'dw.journal_path'} || '/';
            }
            elsif ( $uri =~ m!^/(?:~|users/)([\w-]+)(.*)$! ) {
                ( $journal_user, $journal_path ) = ( $1, $2 || '/' );
            }

            if ($journal_user) {
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

    return;
}

# Render the error document configured for the current (error) status into the
# response, preserving that status. Mirrors the ErrorDocument directives that
# Apache::LiveJournal sets up (see modperl_subs.pl): only 404 and 500 have
# custom documents; any other status keeps its empty body, exactly as Apache
# would (it defines no ErrorDocument for them).
sub _render_error_document {
    my $r = $_[0];

    my $status = $r->status;

    eval {
        if ( $status == 404 ) {

            # Apache renders /internal/local/404 (site-specific, with quips)
            # and falls back to the stock /internal/404 page.
            my $ret = DW::Routing->call( uri => "/internal/local/404" );
            $ret //= DW::Routing->call( uri => "/internal/404" );
        }
        elsif ( $status == 500 ) {

            # Apache serves the static htdocs/500-error.html (a site-local copy
            # overrides the base one). It's padded so browsers don't swap in
            # their own "friendly" error page.
            my $file = LJ::resolve_file('htdocs/500-error.html');
            my $body;
            if ( $file && open my $fh, '<', $file ) {
                local $/;
                $body = <$fh>;
                close $fh;
            }
            else {

                # Never leave a blank 500 (the very symptom this code avoids).
                # Log the resolution failure and fall back to a small inline page.
                warn "Could not serve htdocs/500-error.html"
                    . ( defined $file ? " ($file): $!" : " (not found)" );
                $body =
                      "<h1>Oops!</h1>\n<p>If you've gotten this error, it means "
                    . "that something is currently (and, with luck, temporarily) "
                    . "broken. Please wait five minutes and try again.</p>\n";
            }
            $r->content_type('text/html; charset=utf-8');
            $r->print($body);
        }
        1;
    } or warn "Failed to render error document for status $status: $@";

    # The error templates return OK on success without touching the status, but
    # restore it explicitly so a rendered document can never downgrade the code.
    $r->status($status);
}

# Apply the middleware. Ordering is important!
builder {

    # Render exceptions as an HTML stack trace in dev so developers see the error
    # in the browser (Plack enables this by default but we run with
    # --no-default-middleware). Production omits it so errors don't leak internals.
    enable 'StackTrace' if $LJ::IS_DEV_SERVER;

    # Set a write timeout on the client socket so workers don't block for minutes
    # if the ALB/client disconnects mid-response
    enable 'DW::WriteTimeout', timeout => 5;

    # Handle OPTIONs requests and otherwise only allow the methods that we expect
    # to be allowed; this will abort any calls that are methods that not accepted
    enable 'Options', allowed => [qw /DELETE GET HEAD POST PUT/];

    # Security headers on all responses (matches Apache::LiveJournal::trans)
    enable 'DW::SecurityHeaders';

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

    # JSON access log for Grafana Loki (after XForwardedFor so we log the real IP).
    # Also writes to $ENV{DW_ACCESS_LOG} on disk when set (e.g. via bin/starman --log).
    enable 'DW::AccessLog',
        ( $ENV{DW_ACCESS_LOG} ? ( log_file => $ENV{DW_ACCESS_LOG} ) : () );

    # Strip the response body from HEAD requests while leaving headers intact.
    # Apache does this automatically; under Plack we must opt in or handlers
    # (including the error documents below) would send a body on HEAD. Enabled
    # outside ContentLength so Content-Length still reflects the GET body.
    enable 'Head';

    # Set Content-Length on responses so Starman doesn't fall back to chunked
    # transfer encoding when the app doesn't set it itself
    enable 'ContentLength';

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

    # Rate limiting (after auth and sysban, before request dispatch)
    enable 'DW::RateLimit';

    $app;
};
