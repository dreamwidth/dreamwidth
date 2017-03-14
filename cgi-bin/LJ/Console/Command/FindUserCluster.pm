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

package LJ::Console::Command::FindUserCluster;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "find_user_cluster" }

sub desc { "List the name of the cluster a user is on. Requires priv: supportviewscreened or supporthelp." }

sub args_desc { [
                 'user' => "Username of the account to look up",
                 ] }

sub usage { '<user>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && ( $remote->has_priv( "supportviewscreened" ) || $remote->has_priv( "supporthelp" ) );
}

sub execute {
    my ($self, $user, @args) = @_;

    return $self->error("This command takes one argument. Consult the reference.")
        unless $user && scalar(@args) == 0;

    my $u = LJ::load_user($user);
    return $self->error("Invalid username $user")
        unless $u;

    my $cluster = LJ::DB::get_cluster_description( $u->{clusterid} );
    return $self->print("$user is on the $cluster cluster");
}

1;
