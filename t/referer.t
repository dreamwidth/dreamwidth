# -*-perl-*-

use strict;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
require 'weblib.pl';

plan tests => 18;

{
    note( '$LJ::SITEROOT not set up. Setting up for the test.' ) unless $LJ::SITEROOT;
    $LJ::SITEROOT ||= "http://$LJ::DOMAIN_WEB";

    # first argument is the page we want to check against (system-provided)
    # second argument is the page the user said they were coming from
    ok( LJ::check_referer( "/page.bml", "$LJ::SITEROOT/page.bml" ), "Visited page with bml extension; uri check has .bml." );
    ok( LJ::check_referer( "/page.bml", "$LJ::SITEROOT/page" ), "Visited page with no bml extension; uri check has .bml" );
    ok( LJ::check_referer( "/page", "$LJ::SITEROOT/page.bml" ), "Visited page with bml extension; uri check has no .bml" );
    ok( LJ::check_referer( "/page", "$LJ::SITEROOT/page" ), "Visited page with no bml extension; uri check has .bml" );


    note( '$LJ::SSLROOT not set up. Setting up for the test.' ) unless $LJ::SSLROOT;
    $LJ::SSLROOT ||= "https://$LJ::DOMAIN_WEB";

    ok( LJ::check_referer( "/page", "$LJ::SSLROOT/page" ), "Checking the SSLROOT" );


    my $somerandomsiteroot = "http://www.somerandomsite.org";
    ok( LJ::check_referer( "", $LJ::SITEROOT ), "Check if SITEROOT is on our site" );
    ok( LJ::check_referer( "", "$LJ::SITEROOT/page" ), "Check if any page on our site is on our site" );
    ok( LJ::check_referer( "", $LJ::SSLROOT ), "Check if SSLROOT is on our site" );
    ok( ! LJ::check_referer( "", $somerandomsiteroot ), "Check if somerandomsite is on our site" );

    ok( ! LJ::check_referer( "/page.bml", "$LJ::SITEROOT/page.bmls" ), "Visited page with invalid extension .bmls; uri should be page.bml." );
    ok( ! LJ::check_referer( "/page.bml", "$LJ::SITEROOT/page.html" ), "Visited page with invalid extension .html; uri should be page.bml." );


    ok( LJ::check_referer( "/page", "$LJ::SITEROOT/page.bmls" ), "Visited page with invalid extension .bmls; uri can be page.*" );
    ok( LJ::check_referer( "/page", "$LJ::SITEROOT/page.html" ), "Visited page with invalid extension .html; uri can be page.*" );


    ok( ! LJ::check_referer( "/page", "/page" ), "Passed in a bare URI as a referer" );
    ok( ! LJ::check_referer( "/page", "$LJ::SITEROOT/prefix-page" ), "Visited URL does not match referer URL. (Added prefix)" );
    ok( LJ::check_referer( "/page", "$LJ::SITEROOT/page?argument" ), "Visited URL matches referer URL (with arguments)" );


    ok( ! LJ::check_referer( "/page", "$LJ::SITEROOT/" ), "Visited bare SITEROOT" );
    ok( ! LJ::check_referer( "/page", "$somerandomsiteroot/page" ), "Visited SITEROOT is not from our domain" );
}

1;

