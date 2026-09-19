#!/usr/bin/perl
#
# DW::Controller::Mobile::Login
#
# Sends mobile sign-in through the shared browser login flow.
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

package DW::Controller::Mobile::Login;

use strict;

use DW::Request;
use DW::Routing;

DW::Routing->register_string( "/mobile/login", \&login_handler, app => 1 );

sub login_handler {
    my $r = DW::Request->get;
    return $r->redirect("$LJ::SITEROOT/login?returnto=%2Fmobile%2F");
}

1;
