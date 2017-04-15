#!/usr/bin/perl
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;
use LJ::Config;
LJ::Config->load;
use Apache::BML;

BML::register_block("DOMAIN", "S", $LJ::DOMAIN);
BML::register_block("IMGPREFIX", "S", $LJ::IMGPREFIX);
BML::register_block("SSLIMGPREFIX", "S", $LJ::SSLIMGPREFIX);
BML::register_block("STATPREFIX", "S", $LJ::STATPREFIX);
BML::register_block("SSLSTATPREFIX", "S", $LJ::SSLSTATPREFIX);
BML::register_block("SITEROOT", "S", $LJ::SITEROOT);
BML::register_block("SITENAME", "S", $LJ::SITENAME);
BML::register_block("ADMIN_EMAIL", "S", $LJ::ADMIN_EMAIL);
BML::register_block("SUPPORT_EMAIL", "S", $LJ::SUPPORT_EMAIL);
BML::register_block("CHALRESPJS", "", $LJ::COMMON_CODE{'chalresp_js'});
BML::register_block("JSPREFIX", "S", $LJ::JSPREFIX);
BML::register_block("SSLJSPREFIX", "S", $LJ::SSLJSPREFIX);

# dynamic blocks to implement calling our ljuser function to generate HTML
#    <?ljuser banana ljuser?>
#    <?ljcomm banana ljcomm?>
#    <?ljuserf banana ljuserf?>
BML::register_block("LJUSER", "DS", sub { LJ::ljuser($_[0]->{DATA}); });
BML::register_block("LJCOMM", "DS", sub { LJ::ljuser($_[0]->{DATA}); });
BML::register_block("LJUSERF", "DS", sub { LJ::ljuser($_[0]->{DATA}, { full => 1 }); });

# dynamic needlogin block, needs to be dynamic so we can get at the full URLs and
# so we can translate it
BML::register_block("NEEDLOGIN", "", sub {

    my $uri = BML::get_uri();
    if (my $qs = BML::get_query_string()) {
        $uri .= "?" . $qs;
    }
    $uri = LJ::eurl($uri);

    return BML::redirect("$LJ::SITEROOT/?returnto=$uri");
});

{
    my $dl = "<a href=\"$LJ::SITEROOT/files/%%DATA%%\">HTTP</a>";
    BML::register_block("DL", "DR", $dl);
}

BML::register_block("METACTYPE", "S", '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">');


1;
