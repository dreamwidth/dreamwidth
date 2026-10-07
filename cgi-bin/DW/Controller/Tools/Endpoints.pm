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
#
# DW::Controller::Tools::Endpoints - AJAX endpoint(s) used by the entry editor.
# Migrated from htdocs/tools/endpoints/ljuser.bml.

package DW::Controller::Tools::Endpoints;

use strict;

use DW::Routing;
use DW::Request;
use DW::RPC;

use DW::External::User;

DW::Routing->register_string(
    "/tools/endpoints/ljuser", \&ljuser_handler,
    app    => 1,
    format => 'json'
);

# Resolve a username (optionally on an external site) to its rendered
# <user>/ljuser markup, for the rich-text editor's user-tag insertion.
sub ljuser_handler {
    my $r    = DW::Request->get;
    my $post = $r->post_args;

    my $username = $post->{username};
    my $site     = $post->{site};

    my %ret;
    my $u;

    if ($site) {

        # verify that this is a proper site
        $u = DW::External::User->new( user => $username, site => $site );
        if ($u) {
            $ret{userstr} = '<user site="' . $u->site->{domain} . '" name="' . $u->user . '">';
            $ret{ljuser}  = $u->ljuser_display;
        }
    }

    unless ($u) {
        $u            = LJ::load_user($username);
        $ret{userstr} = "<user name=\"$username\">";
        $ret{ljuser}  = LJ::ljuser($u);
    }

    # more general error message if we may have been trying to show an external site
    return DW::RPC->err("Error: Invalid user or site") if $site && !$u;

    # more specific error message if we are loading a user on the site
    return DW::RPC->err("Error: No such user") unless $u;

    sleep(1.5) if $LJ::IS_DEV_SERVER;

    $ret{success} = 1;
    return DW::RPC->out(%ret);
}

1;
