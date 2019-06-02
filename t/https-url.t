# t/https-url.t
#
# Test LJ::CleanHTML::https_url.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Jen Griffin <kareila@livejournal.com>
#
# Copyright (c) 2015-2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::CleanHTML;

# make sure we have a working proxy subroutine for testing
local $LJ::PROXY_URL = "https://proxy.myhost.net";
unless ( $LJ::PROXY_SALT_FILE && -e $LJ::PROXY_SALT_FILE ) {
    no warnings 'redefine';
    *DW::Proxy::get_url_signature = sub { return 'testfoo' };
}

my @urls = (

    # internal links
    [ "https://example.$LJ::DOMAIN/file/foo", "https://example.$LJ::DOMAIN/file/foo" ],
    [ "http://example.$LJ::DOMAIN/file/foo",  "https://example.$LJ::DOMAIN/file/foo" ],

    # external links
    [ "https://example.com/a.png", "https://example.com/a.png" ],
    [ "http://example.com/a.png",  DW::Proxy::get_proxy_url("http://example.com/a.png") ],

    # protocol relative links
    [ "//example.com/a.png", "//example.com/a.png" ],

    # links that can be upgraded via KNOWN_HTTPS_SITES
    [ "http://xkcd.com/file/foo",           "https://xkcd.com/file/foo" ],
    [ "http://username.blogspot.com/a.png", "https://username.blogspot.com/a.png" ],

    # link that includes a space - will be transformed into %20 by the browser
    [ "http://example.com/a%20b.png", DW::Proxy::get_proxy_url("http://example.com/a b.png") ],
);

local %LJ::KNOWN_HTTPS_SITES = qw( xkcd.com 1 blogspot.com 1 );

plan tests => scalar @urls;

for (@urls) {
    my $url       = $_->[0];
    my $https_url = LJ::CleanHTML::https_url($url);
    is( $https_url, $_->[1], "https url for $url" );
}
