#!/usr/bin/perl
#
# Plack::Middleware::DW::Auth
#
# Plack middleware that supports authentication for the Dreamwidth system.
# Determines the logged-in user from session cookies and sets the remote
# user for the duration of the request. On dev servers, supports the
# ?as=username parameter for impersonation.
#
# Ported from the auth flow in Apache::LiveJournal::trans() and
# LJ::get_remote() in LJ::User::Login.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2021-2025 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package Plack::Middleware::DW::Auth;

use strict;
use v5.10;

use parent qw/ Plack::Middleware /;

use DW::Request;
use LJ::Session;

sub call {
    my ( $self, $env ) = @_;

    my $r = DW::Request->get;

    # Resolve authenticated user from session cookies. We do this directly
    # rather than calling LJ::get_remote() because that function uses
    # BML::get_request() for its web context check, which doesn't work
    # under Plack. By resolving the session here and calling set_remote(),
    # subsequent calls to LJ::get_remote() will hit the cache and work.
    my $sessobj =
        LJ::Session->session_from_cookies( redirect_ref => \$LJ::CACHE_REMOTE_BOUNCE_URL, );

    if ( $sessobj && $sessobj->owner ) {
        my $u = $sessobj->owner;
        $sessobj->try_renew;
        $u->{'_session'} = $sessobj;
        LJ::User->set_remote($u);

        # Activity tracking (matches Apache path behavior)
        if ( @LJ::MEMCACHE_SERVERS && LJ::is_enabled('active_user_tracking') ) {
            push @LJ::CLEANUP_HANDLERS, sub { $u->note_activity('A') };
        }
    }
    else {
        # Mark auth as resolved so LJ::get_remote() won't re-enter session resolution
        LJ::User->set_remote(undef);

        # If we're on a journal subdomain and the domain session cookie is
        # missing or stale, session_from_cookies will have set a bounce URL
        # pointing to /misc/get_domain_session. Redirect now so the cookie
        # gets refreshed before we render the page as logged-out.
        # Skip on POST (form submissions shouldn't be redirected).
        # Skip when dw.skip_domain_bounce is set (e.g., userpic subdomain
        # serving public images that don't need authentication).
        unless ( $r->did_post || $env->{'dw.skip_domain_bounce'} ) {
            my $burl = LJ::remote_bounce_url();
            return $r->redirect($burl) if $burl;
        }
    }

    # Dev-only: allow ?as=username to impersonate any user for testing.
    # Pass ?as=<invalid> to view as logged out. NEVER enable in production.
    if ($LJ::IS_DEV_SERVER) {
        my $as = $r->get_args->{as};
        if ( defined $as && $as =~ /^\w{1,25}$/ ) {
            my $ru = LJ::load_user($as);
            LJ::set_remote($ru);    # might be undef, to allow for "view as logged out"
        }
    }

    return $self->app->($env);
}

1;
