#!/usr/bin/perl
# t/plack-shop-bounce.t
#
# Test that the domain session bounce on the shop subdomain returns the user
# to the URL they asked for, not to the internally rewritten /shop path.
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

use strict;
use warnings;
use v5.10;

use Test::More;
use HTTP::Request::Common;
use Plack::Test;
use URI;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

plan tests => 4;

my $app = do "$ENV{LJHOME}/app.psgi";
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Session resolution stays real so the bounce is computed by LJ::Session;
# only middleware concerns not under test are disabled.
{
    no warnings 'redefine', 'once';
    *LJ::sysban_check                    = sub { return 0 };
    *LJ::Sysban::tempban_check           = sub { return 0 };
    *LJ::UniqCookie::parts_from_cookie   = sub { return () };
    *LJ::UniqCookie::ensure_cookie_value = sub { return };
    *DW::RateLimit::get                  = sub { return undef };
}

local $LJ::USER_DOMAIN = 'example.org';
local $LJ::DOMAIN_WEB  = 'www.example.org';
local $LJ::DOMAIN      = 'example.org';
local $LJ::SITEROOT    = 'https://www.example.org';
local $LJ::PROTOCOL    = 'https';
local %LJ::SUBDOMAIN_FUNCTION = ();    # shop is served in place, as in production

# A logged-in browser (ljloggedin set) that has no shop domain session cookie
# yet gets bounced to get_domain_session; return= is where it lands afterwards.
sub bounce_return {
    my ($url) = @_;
    my $res;
    test_psgi $app, sub {
        my $cb = shift;
        $res = $cb->( GET $url, Cookie => 'ljloggedin=u1:s1' );
    };
    return ( $res, URI->new( $res->header('Location') // '' )->query_param('return') );
}

{
    my ( $res, $return ) = bounce_return('https://shop.example.org/');
    ok( $res->is_redirect, "shop root without domain cookie bounces" );
    is( $return, 'https://shop.example.org/', "bounce returns to the shop root, not /shop" );
}

{
    my ( $res, $return ) = bounce_return('https://shop.example.org/cart?newcart=1');
    ok( $res->is_redirect, "shop page without domain cookie bounces" );
    is(
        $return,
        'https://shop.example.org/cart?newcart=1',
        "bounce returns to the requested shop page and keeps its arguments"
    );
}
