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

package LJ::Console::Command::Community;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "community" }

sub desc { "Add or remove a user from a community. Requires priv: none." }

sub args_desc {
    [
        'community' => "The username of the community.",
        'action'    => "Only 'remove' is supported right now.",
        'user'      => "The user you want to remove from the community.",
    ]
}

sub usage { '<community> <action> <user>' }

sub can_execute { 1 }

sub execute {
    my ( $self, $commname, $action, $user, @args ) = @_;
    my $remote = LJ::get_remote();

    return $self->error("This command takes exactly three arguments. Consult the reference")
        unless $commname && $action && $user && scalar(@args) == 0;

    my $comm   = LJ::load_user($commname);
    my $target = LJ::load_user($user);

    return $self->error("Adding users to communities with the console is disabled.")
        if $action eq 'add';

    return $self->error("Unknown action: only 'remove' is currently supported.")
        unless $action eq 'remove';

    return $self->error("Unknown community: $commname")
        unless $comm && $comm->is_community;

    return $self->error("Unknown user: $user")
        unless $target;

    my $can_add = $remote
        && ( $remote->can_manage($comm)
        || $remote->has_priv( "sharedjournal", "*" ) );
    my $can_remove = $can_add || ( $remote && $remote->equals($target) );

    return $self->error("You cannot add users to this community.")
        if $action eq 'add' && !$can_add;

    return $self->error("You cannot remove users from this community.")
        if $action eq 'remove' && !$can_remove;

    # since adds are blocked, at this point we know we're removing the user
    $target->leave_community($comm);
    return $self->print( "User " . $target->user . " removed from " . $comm->user );
}

1;
