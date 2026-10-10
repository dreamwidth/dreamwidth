#!/usr/bin/perl
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

package DW::Controller::FCKPoll;

use strict;
use warnings;
use DW::Request;
use DW::Routing;
use DW::Template;

DW::Routing->register_string( '/tools/fck_poll', \&fck_poll_handler, app => 1, no_cache => 1 );

sub fck_poll_handler {
    my $r = DW::Request->get;
    $r->content_type('text/html; charset=utf-8');
    return DW::Template->render_template( 'entry/fck-poll.tt', {}, { no_sitescheme => 1 } );
}

1;
