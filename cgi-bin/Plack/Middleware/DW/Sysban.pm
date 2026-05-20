#!/usr/bin/perl
#
# Plack::Middleware::DW::Sysban
#
# Checks incoming requests against system bans (IP, uniq cookie, tempbans)
# and returns 403 for banned requests. Ported from the sysban checks in
# Apache::LiveJournal::trans().
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package Plack::Middleware::DW::Sysban;

use strict;
use v5.10;

use parent qw/ Plack::Middleware /;

use LJ::Sysban;
use LJ::UniqCookie;

sub call {
    my ( $self, $env ) = @_;

    my $uri = $env->{PATH_INFO};

    # Don't block the blocked-bot URI itself (avoids redirect loop)
    my $is_blocked_uri = $LJ::BLOCKED_BOT_URI && index( $uri, $LJ::BLOCKED_BOT_URI ) == 0;

    unless ($is_blocked_uri) {
        my @ips = _request_ips($env);

        # Check uniq cookie sysban
        if ( my @cookieparts = LJ::UniqCookie->parts_from_cookie ) {
            my ($uniq) = @cookieparts;
            return _blocked_bot($env)
                if LJ::sysban_check( 'uniq', $uniq );
        }

        # Check IP sysbans
        foreach my $ip (@ips) {
            return _blocked_bot($env)
                if LJ::sysban_check( 'ip', $ip );
        }

        # Check temporary IP bans
        return _blocked_bot($env)
            if LJ::Sysban::tempban_check( ip => \@ips );

        # Check noanon_ip bans (only for non-authenticated requests)
        unless ( LJ::get_remote() ) {

            # Allow login-related paths through
            unless ( $uri =~ m!^(?:/login|/__setdomsess|/misc/get_domain_session)! ) {
                foreach my $ip (@ips) {
                    return _blocked_anon()
                        if LJ::sysban_check( 'noanon_ip', $ip );
                }
            }
        }
    }

    return $self->app->($env);
}

sub _request_ips {
    my ($env) = @_;

    # Use the remote IP as resolved by XForwardedFor middleware
    my $ip  = LJ::get_remote_ip();
    my @ips = ($ip) if $ip;

    # Also check all X-Forwarded-For IPs, same as Apache path
    if ( my $forward = $env->{HTTP_X_FORWARDED_FOR} ) {
        my %seen = map { $_ => 1 } split( /\s*,\s*/, $forward );
        push @ips, keys %seen;
    }

    return @ips;
}

sub _blocked_bot {
    my ($env) = @_;

    my $subject = $LJ::BLOCKED_BOT_SUBJECT || "403 Denied";
    my $message = $LJ::BLOCKED_BOT_MESSAGE || "You don't have permission to view this page.";

    if ($LJ::BLOCKED_BOT_INFO) {
        my $ip   = LJ::get_remote_ip();
        my $uniq = LJ::UniqCookie->current_uniq;
        $message .= " $uniq @ $ip";
    }

    my $body = "<h1>$subject</h1>$message";
    return [ 403, [ 'Content-Type' => 'text/html' ], [$body] ];
}

sub _blocked_anon {
    my $subject = "403 Denied";
    my $message =
"You don't have permission to access $LJ::SITENAME. Please first <a href='$LJ::SITEROOT/login'>log in</a>.";

    my $body =
          "<html><head><title>$subject</title></head><body>"
        . "<h1>$subject</h1> $message"
        . "</body></html>";
    return [ 403, [ 'Content-Type' => 'text/html' ], [$body] ];
}

1;
