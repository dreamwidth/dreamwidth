# t/https-url.t
#
# Test LJ::CleanHTML::https_url.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2015 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

use lib "$ENV{LJHOME}/cgi-bin";
BEGIN { $LJ::_T_CONFIG = 1; require 'ljlib.pl'; }
use LJ::CleanHTML;

my @urls = (
    # internal links
    [ "https://example.$LJ::DOMAIN/file/foo", "https://example.$LJ::DOMAIN/file/foo" ],
    [ "http://example.$LJ::DOMAIN/file/foo",  "https://example.$LJ::DOMAIN/file/foo" ],

    # external links
    [ "https://example.com/a.png", "https://example.com/a.png" ],

    # protocol relative links
    [ "//example.com/a.png", "//example.com/a.png" ],
);

if ( $LJ::USE_SSL ) {
    plan tests => scalar @urls;
} else {
    plan skip_all => "Doesn't work without \$LJ::USE_SSL set";
}

for ( @urls ) {
    my $url = $_->[0];
    my $https_url = LJ::CleanHTML::https_url( $url );
    is( $https_url, $_->[1], "https url for $url" );
}
