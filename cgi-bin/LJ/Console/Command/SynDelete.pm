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

package LJ::Console::Command::SynDelete;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "syn_delete" }

sub desc {
    "Deletes a syndicated (RSS/Atom feed) account, marking it for purging and stopping the "
        . "syndication system from refreshing it. Pass 'undelete' to reverse this and resume "
        . "feed checking. Requires priv: syn_edit.";
}

sub args_desc {
    [
        'user'   => "The username of the syndicated account.",
        'action' => "Either 'delete' (the default) or 'undelete' to restore a deleted feed.",
    ]
}

sub usage { '<user> [ delete | undelete ]' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv("syn_edit");
}

sub execute {
    my ( $self, $user, $action, @args ) = @_;

    $action ||= 'delete';

    return $self->error("This command takes one or two arguments. Consult the reference.")
        unless $user && scalar(@args) == 0;

    return $self->error("Invalid action: must be 'delete' or 'undelete'.")
        unless $action eq 'delete' || $action eq 'undelete';

    my $u = LJ::load_user($user);

    return $self->error("Invalid user $user")
        unless $u;
    return $self->error("Not a syndicated account")
        unless $u->is_syndicated;
    return $self->error("Cannot modify a purged account.")
        if $u->is_expunged;

    my $remote = LJ::get_remote();

    if ( $action eq 'delete' ) {
        return $self->error("Account is already deleted.")
            if $u->is_deleted;

        $u->set_deleted;

        LJ::statushistory_add( $u, $remote, 'synd_delete',
            "Feed account deleted; syndication checking stopped." );

        return $self->print( "Feed account $user marked as deleted; "
                . "the syndication system will stop refreshing it." );
    }
    else {
        return $self->error("Account is not deleted.")
            unless $u->is_deleted;

        $u->set_visible;

        # nudge the scheduler to pick the feed up promptly and clear any
        # accumulated failures from before it was deleted.
        my $dbh = LJ::get_db_writer();
        $dbh->do( "UPDATE syndicated SET checknext=NOW(), failcount=0 WHERE userid=?",
            undef, $u->id );

        LJ::statushistory_add( $u, $remote, 'synd_delete',
            "Feed account undeleted; syndication checking restored." );

        return $self->print(
            "Feed account $user restored; " . "the syndication system will resume refreshing it." );
    }
}

1;
