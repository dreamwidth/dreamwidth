#!/usr/bin/perl
#
# This code is based on code originally created by the LiveJournal project
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
# Authors:
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2020 by Dreamwidth Studios, LLC.

package DW::Controller::CSSProxy;

use strict;

use DW::Controller;
use DW::Routing;

use LJ::CSS::Cleaner;
use Digest::SHA1;
use URI::URL;

DW::Routing->register_string( '/extcss', \&extcss_handler, app => 1 );

sub extcss_handler {
    my ( $ok, $rv ) = controller( anonymous => 1, skip_domsess => 1 );
    return $rv unless $ok;

    my $r = $rv->{r};

    my $print = sub {
        $r->content_type("text/css");
        $r->print( $_[0] );
        return $r->OK;
    };

    # don't allow access via www.
    my $host = lc $r->header_in("Host");
    $host =~ s/:.*//;    # remove port numbers
    if (

        $host eq $LJ::DOMAIN || $host eq $LJ::DOMAIN_WEB
        )

    {
        return $print->("/* invalid domain */");
    }

    # we should have one GET param: u is the URL of the stylesheet to be cleaned
    my $url = $r->get_args->{u};

    return $print->("/* invalid URL */")
        unless $url
        and $url =~ m{^https?://}
        and $url !~ /[<>]/;

    my $memkey = "css:" . Digest::SHA1::sha1_hex($url);

    if ( my $cached_clean = LJ::MemCache::get($memkey) ) {
        return $print->($cached_clean);
    }

    my $ua = LJ::get_useragent(
        role     => "extcss",
        timeout  => $LJ::CSS_FETCH_TIMEOUT || 2,
        max_size => 1024 * 300,
    );
    my $res = $ua->get($url);

    unless ( $res->is_success ) {
        my $errmsg = $res->error_as_HTML;
        $errmsg =~ s/<.+?>//g;
        $errmsg =~ s/[^\w ]/ /g;
        $errmsg =~ s/\s+/ /g;
        return $print->("/* Error fetching CSS: $errmsg */");
    }

    my $pragma  = $res->header("Pragma");
    my $nocache = $pragma && $pragma =~ /no-cache/i;

    my $unclean = $res->content;

    # Braindead URL rewriting. Once there's a proper CSS parser
    # behind the CSS cleaner this can be done more intelligently,
    # but this should do for now aside from some odd-ball cases.
    # We do this before CSS cleaning to avoid this being used to introduce nasties.
    $unclean =~ s/\burl\(([\"\']?)(.+?)\1\)/ 'url('.URI::URL->new($2, $url)->abs().')' /egi;

    my $cleaner = LJ::CSS::Cleaner->new;
    my $clean   = $cleaner->clean($unclean);

    LJ::Hooks::run_hook( 'css_cleaner_transform', \$clean );

    LJ::MemCache::set( $memkey, $clean, 300 ) unless $nocache;    # 5 minute caching
    return $print->($clean);
}

1;
