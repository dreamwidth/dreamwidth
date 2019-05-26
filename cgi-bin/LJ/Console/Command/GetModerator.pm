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

package LJ::Console::Command::GetModerator;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "get_moderator" }

sub desc {
"Given a community username, lists all moderators. Given a user account, lists all communities that the user moderates. Requires priv: finduser.";
}

sub args_desc {
    [ 'user' => "The username of the account you want to look up.", ]
}

sub usage { '<user>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv("finduser");
}

sub execute {
    my ( $self, $user, @args ) = @_;

    return $self->error("This command takes exactly one argument. Consult the reference.")
        unless $user && scalar(@args) == 0;

    my $relation = LJ::Console::Command::GetRelation->new(
        command => 'get_maintainer',
        args    => [ $user, 'M' ]
    );
    $relation->execute( $relation->args );
    $self->add_responses( $relation->responses );

    return 1;
}

1;
