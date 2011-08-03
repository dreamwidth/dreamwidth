#!/usr/bin/perl
#
# This code was based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and expanded
# by Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
#
# DW::Hooks::EmbedWhitelist
#
# Keep a whitelist of trusted sites which we trust for certain kinds of embeds
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.

package DW::Hooks::EmbedWhitelist;

use strict;
use LJ::Hooks;
use URI;

sub match_subdomain {
    my $want_domain = $_[0];
    my $domain_from_uri = $_[1];

    return $domain_from_uri =~ /^(?:[\w.-]*\.)?\Q$want_domain\E$/;
}

sub match_full_path {
    my $want_path = $_[0];
    my $path_from_uri = $_[1];

    return $path_from_uri =~ /^$want_path$/;
}

LJ::Hooks::register_hook( 'allow_iframe_embeds', sub {
    my ( $embed_url, %opts ) = @_;

    return 0 unless $embed_url;

    my $parsed_uri = URI->new( $embed_url );

    my $uri_scheme = $parsed_uri->scheme;
    return 0 unless $uri_scheme eq "http" || $uri_scheme eq "https";

    my $uri_host = $parsed_uri->host;
    my $uri_path = $parsed_uri->path;   # not including query

    ## YouTube (http://apiblog.youtube.com/2010/07/new-way-to-embed-youtube-videos.html)
    if ( match_subdomain( "youtube.com", $uri_host ) || match_subdomain( "youtube-nocookie.com", $uri_host ) ) {
        return 1 if match_full_path( qr!/embed/[-_a-zA-Z0-9]{11,}!, $uri_path );
    }

    return 0;

} );

1;
