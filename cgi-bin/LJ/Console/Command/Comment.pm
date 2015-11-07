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

package LJ::Console::Command::Comment;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "comment" }

sub desc { "Manage comments in an account. Requires priv: deletetalk." }

sub args_desc { [
                 'action' => 'One of: screen, unscreen, freeze, unfreeze, delete, delete_thread.',
                 'url' => 'The URL to the comment. (Use the permanent link that shows this comment topmost.)',
                 'reason' => 'Reason this action is being taken.',
                 ] }

sub usage { '<action> <url> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "deletetalk" );
}

sub execute {
    my ($self, $action, $uri, $reason, @args) = @_;

    return $self->error("This command takes three arguments. Consult the reference.")
        unless $action && $uri && $reason && scalar(@args) == 0;

    return $self->error("Action must be one of: screen, unscreen, freeze, unfreeze, delete, delete_thread.")
        unless $action =~ /^(?:screen|unscreen|freeze|unfreeze|delete|delete_thread)$/;

    return $self->error("You must provide a reason to action a comment.")
        unless $reason;

    my $comment = LJ::Comment->new_from_url($uri);
    return $self->error("URL provided does not appear to link to a valid comment.")
        unless $comment && $comment->valid;
    return $self->error("Comment is already deleted, so no further action is possible.")
        if $comment->is_deleted;

    my $u = $comment->journal;
    my ($ditemid, $dtalkid) = ($comment->entry->ditemid, $comment->dtalkid);
    my ($jitemid, $jtalkid) = ($comment->entry->jitemid, $comment->jtalkid);

    if ($action eq 'freeze') {
        return $self->error("Comment is already frozen.")
            if $comment->is_frozen;
        LJ::Talk::freeze_thread($u, $jitemid, $jtalkid);

    } elsif ($action eq 'unfreeze') {
        return $self->error("Comment is not frozen.")
            unless $comment->is_frozen;
        LJ::Talk::unfreeze_thread($u, $jitemid, $jtalkid);

    } elsif ($action eq 'screen') {
        return $self->error("Comment is already screened.")
            if $comment->is_screened;
        LJ::Talk::screen_comment($u, $jitemid, $jtalkid);

    } elsif ($action eq 'unscreen') {
        return $self->error("Comment is not screened.")
            unless $comment->is_screened;
        LJ::Talk::unscreen_comment($u, $jitemid, $jtalkid);

    } elsif ($action eq 'delete') {
        LJ::Talk::delete_comment($u, $jitemid, $jtalkid, $comment->state);

    } elsif ($action eq 'delete_thread') {
        LJ::Talk::delete_thread($u, $jitemid, $jtalkid);
    }

    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, 'comment_action', "$action (entry $ditemid comment $dtalkid): $reason");

    return $self->print("Comment action taken.");
}

1;
