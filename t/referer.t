# t/referer.t
#
# Test LJ::check_referer.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 23;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Web;

{
    note('$LJ::SITEROOT not set up. Setting up for the test.') unless $LJ::SITEROOT;
    $LJ::SITEROOT ||= "http://$LJ::DOMAIN_WEB";

    # first argument is the page we want to check against (system-provided)
    # second argument is the page the user said they were coming from

    note("basic tests");
    ok(
        LJ::check_referer( "/page.bml", "$LJ::SITEROOT/page.bml" ),
        "Visited page with bml extension; uri check has .bml."
    );
    ok(
        LJ::check_referer( "/page.bml", "$LJ::SITEROOT/page" ),
        "Visited page with no bml extension; uri check has .bml"
    );
    ok(
        LJ::check_referer( "/page", "$LJ::SITEROOT/page" ),
        "Visited page with no bml extension; uri check has .bml"
    );

    note("checking domain / siteroot ");
    my $somerandomsiteroot = "http://www.somerandomsite.org";
    ok( LJ::check_referer( "", $LJ::SITEROOT ), "Check if SITEROOT is on our site" );
    ok(
        LJ::check_referer( "", "$LJ::SITEROOT/page" ),
        "Check if any page on our site is on our site"
    );
    ok( !LJ::check_referer( "", $somerandomsiteroot ), "Check if somerandomsite is on our site" );
    ok( !LJ::check_referer( "", "${LJ::SITEROOT}.other.tld" ),
        "Check if another site which begins with our SITEROOT is on our site" );
    ok( !LJ::check_referer( "/page", "/page" ), "Passed in a bare URI as a referer" );

    note("checking extensions");
    ok(
        !LJ::check_referer( "/page.bml", "$LJ::SITEROOT/page.bmls" ),
        "Visited page with invalid extension .bmls; uri should be page.bml."
    );
    ok(
        !LJ::check_referer( "/page.bml", "$LJ::SITEROOT/page.html" ),
        "Visited page with invalid extension .html; uri should be page.bml."
    );

    ok(
        !LJ::check_referer( "/page", "$LJ::SITEROOT/page.bml" ),
        "Visited page with bml extension; uri check has no .bml"
    );
    ok(
        !LJ::check_referer( "/page", "$LJ::SITEROOT/page.bmls" ),
        "Visited page with invalid extension .bmls (bml+suffix)"
    );
    ok( !LJ::check_referer( "/page", "$LJ::SITEROOT/page.html" ),
        "Visited page with invalid extension .html (nothing that looks like bml)" );

    note("checking for partial matches (should not match)");
    ok(
        !LJ::check_referer( "/page", "$LJ::SITEROOT/prefix-page" ),
        "Visited URL does not match referer URL. (Added prefix)"
    );
    ok(
        !LJ::check_referer( "/page", "$LJ::SITEROOT/page-suffix" ),
        "Visited URL does not match referer URL. (Added suffix)"
    );
    ok(
        !LJ::check_referer( "/page", "$LJ::SITEROOT/page/other" ),
        "Visited URL does not match referer URL. (Added directory level)"
    );

    ok( !LJ::check_referer( "/page", "$LJ::SITEROOT/" ), "Visited bare SITEROOT" );
    ok( !LJ::check_referer( "/page", "$somerandomsiteroot/page" ),
        "Visited SITEROOT is not from our domain" );

    note("checking for URL arguments");

    # Argument tests where uri does not have an argument
    ok(
        LJ::check_referer( "/page", "$LJ::SITEROOT/page?argument" ),
        "Visited URL matches referer URL (with arguments)"
    );
    ok(
        !LJ::check_referer( "/page", "$LJ::SITEROOT/page.bml?argument" ),
        "Visited .bml URL with arguments matches allowed URL"
    );
    ok(
        LJ::check_referer( "/page.bml", "$LJ::SITEROOT/page?argument" ),
        "Visited non-bml URL with arguments matches allowed .bml URL"
    );
    ok(
        LJ::check_referer( "/page.bml", "$LJ::SITEROOT/page.bml?argument" ),
        "Visited .bml URL with arguments matches allowed .bml URL"
    );

    # Tricks with two question marks in referer
    ok( LJ::check_referer( "/page", "$LJ::SITEROOT/page?argument?suffix" ),
        "Visited page has second question mark followed by suffix; uri check has no arguments" );
}

1;

