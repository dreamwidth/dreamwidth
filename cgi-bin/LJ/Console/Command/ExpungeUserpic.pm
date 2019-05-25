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

package LJ::Console::Command::ExpungeUserpic;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "expunge_userpic" }

sub desc { "Expunge a userpic from the site. Requires priv: siteadmin:userpics." }

sub args_desc {
    [ 'url' => "URL of the userpic to expunge", ]
}

sub usage { '<url>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "siteadmin", "userpics" );
}

sub execute {
    my ( $self, $url, @args ) = @_;

    return $self->error("This command takes one argument. Consult the reference.")
        unless $url && scalar(@args) == 0;

    my ( $userid, $picid );
    if ( $url =~ m!(\d+)/(\d+)/?$! ) {
        $picid  = $1;
        $userid = $2;
    }

    my $u = LJ::load_userid($userid);
    return $self->error("Invalid userpic URL.")
        unless $u;

    my ( $rval, @hookval ) = $u->expunge_userpic($picid);

    return $self->error("Error expunging userpic.") unless $rval;

    foreach my $hv (@hookval) {
        my ( $type, $msg ) = @$hv;
        $self->$type($msg);
    }

    my $remote = LJ::get_remote();
    LJ::statushistory_add( $u, $remote, 'expunge_userpic', "expunged userpic; id=$picid" );

    return $self->print( "Userpic '$picid' for '" . $u->user . "' expunged." );
}

1;
