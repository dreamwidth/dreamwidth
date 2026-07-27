#!/usr/bin/perl
#
# DW::Controller::Mobile::Index
#
# The mobile interface hub (/mobile/): a minimal standalone (no sitescheme)
# menu linking to the mobile login, post, and reading pages, varying on whether
# the viewer is logged in.
#
# This code is based on code originally created by the LiveJournal project
# owned and operated by Live Journal, Inc. The code has been modified and
# expanded by Dreamwidth Studios, LLC. These files were originally licensed
# under the terms of the license supplied by Live Journal, Inc, which made
# its code repository private in 2014. That license is archived here:
#
# https://github.com/apparentlymart/livejournal/blob/master/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#

package DW::Controller::Mobile::Index;

use strict;

use DW::Controller;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( "/mobile/", \&index_handler, app => 1, no_redirects => 1 );

sub index_handler {
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    return DW::Template->render_template( 'mobile/index.tt', $rv, { no_sitescheme => 1 } );
}

1;
