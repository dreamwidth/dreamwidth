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
package DW::Controller::RPC::MiscLegacy;

use strict;
use DW::Routing;
use LJ::JSON;
use LJ::CreatePage;

# do not put any endpoints that do not have the "forked from LJ" header in this file
DW::Routing->register_rpc( "checkforusername", \&check_username_handler, format => 'json' );

sub check_username_handler {
    my $r = DW::Request->get;
    my $args = $r->get_args;
    my $error = LJ::CreatePage->verify_username( $args->{user} );

    $r->print( to_json({ error => $error ? $error : "" }) );
    return $r->OK;
}
