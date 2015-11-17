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

package LJ::Console::Command::GetRelation;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "get_relation" }

sub desc { "Given a username and an edge, looks up all relations. Requires priv: N/A, can't be called directly." }

sub args_desc { [
                 'user' => "The username of the account you want to look up.",
                 'edge' => "The reluser edge to look up.",
                 ] }

sub usage { '<user> <edge>' }

sub can_execute { 0 }  # can't be called directly

sub is_hidden { 1 }

sub execute {
    my ($self, $user, $edge, @args) = @_;

    return $self->error("This command takes exactly two arguments. Consult the reference.")
        unless $user && $edge && scalar(@args) == 0;

    my $u = LJ::load_user($user);
    return $self->error("Invalid user $user")
        unless $u;

    my $ids = $u->is_person ? LJ::load_rel_target($u, $edge) : LJ::load_rel_user($u, $edge);
    my $us = LJ::load_userids(@{$ids || []});

    foreach my $u (sort { $a->id <=> $b->id } values %$us) {
        next unless $u;
        my $finduser = LJ::Console::Command::Finduser->new( command => 'finduser', args => [ 'timeupdate', $u->user ] );
        $finduser->execute($finduser->args);
        $self->add_responses($finduser->responses);
    }

    return 1;
}

1;
