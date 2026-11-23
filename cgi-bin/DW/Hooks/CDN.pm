#!/usr/bin/perl
#
# DW::Hooks::CDN
#
# Hooks that purge userpic URLs from the Bunny CDN edge cache when an icon is
# expunged, suspended, or unsuspended.
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

package DW::Hooks::CDN;

use strict;
use warnings;

use LJ::Hooks;
use HTTP::Request ();
use URI::Escape   ();

# Purge a single userpic URL from the Bunny CDN so a removed or suspended icon
# stops being served from the edge (e.g. for a DMCA takedown), and a restored
# icon comes back immediately instead of waiting out the substituted default's
# short TTL. Fired with ( $picid, $userid ). Returns an [ $type, $msg ] pair the
# console command surfaces to the operator, or nothing when there's no message.
sub purge_userpic {
    my ( $picid, $userid ) = @_;
    return unless $picid && $userid;

    # No key configured (dev/test): nothing to purge against, stay silent.
    my $key = $LJ::BUNNY_CDN_API_KEY
        or return;

    my $url = "$LJ::USERPIC_ROOT/$picid/$userid";

    # Short timeout so a slow or unreachable CDN can't hang the request; the
    # state change has already happened regardless of the purge.
    my $ua = LJ::get_useragent( role => 'cdn_purge', timeout => 5 )
        or return [ 'error', "CDN purge failed for $url: could not create user agent" ];

    # async=true so Bunny queues the purge and returns immediately instead of
    # blocking until edge propagation completes.
    my $req = HTTP::Request->new(
        POST => "https://api.bunny.net/purge?async=true&url=" . URI::Escape::uri_escape($url) );
    $req->header( AccessKey => $key );

    my $res = $ua->request($req);
    return [ 'info',  "Requested CDN purge: $url" ] if $res->is_success;
    return [ 'error', "CDN purge failed for $url: " . $res->status_line ];
}

LJ::Hooks::register_hook( $_, \&purge_userpic )
    foreach qw( expunge_userpic suspend_userpic unsuspend_userpic );

1;
