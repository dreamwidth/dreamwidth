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

use File::Temp ();
use Test::More;

use lib "$ENV{LJHOME}/cgi-bin";
use DW::Proxy;
use LJ::CleanHTML;

my $salt_file = File::Temp->new;
print {$salt_file} 'testfoo';
close $salt_file or die "Cannot write proxy salt: $!";
local $LJ::DOMAIN          = "example.org";
local $LJ::PROXY_URL       = "https://proxy.myhost.net";
local $LJ::PROXY_SALT_FILE = $salt_file->filename;

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

    # links that include non-ASCII characters - the browser requests them as
    # percent-encoded UTF-8, whether the URL is UTF-8 bytes or characters
    [
        "http://example.com/%D1%80%D0%B0-1.jpg",
        DW::Proxy::get_proxy_url("http://example.com/\xD1\x80\xD0\xB0-1.jpg")
    ],
    [
        "http://example.com/%D1%80%D0%B0-1.jpg",
        DW::Proxy::get_proxy_url("http://example.com/\x{0440}\x{0430}-1.jpg")
    ],
    [
        "http://example.com/a.php?f=%D1%80%D0%B0",
        DW::Proxy::get_proxy_url("http://example.com/a.php?f=\xD1\x80\xD0\xB0")
    ],
);

local %LJ::KNOWN_HTTPS_SITES = qw( xkcd.com 1 blogspot.com 1 );

plan tests => scalar @urls;

for (@urls) {
    my $url       = $_->[0];
    my $https_url = LJ::CleanHTML::https_url($url);
    is( $https_url, $_->[1], "https url for $url" );
}
