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

package LJ::Console::Command::BanSet;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "ban_set" }

sub desc { "Ban another user from posting in your journal or community. Requires priv: none." }

sub args_desc {
    [
        'user'      => "The user you want to ban.",
        'community' => "Optional; to ban a user from a community you maintain.",
    ]
}

sub usage { '<user> [ "from" <community> ]' }

sub can_execute { 1 }

sub execute {
    my ( $self, $user, @args ) = @_;
    my $remote  = LJ::get_remote();
    my $journal = $remote;            # may be overridden later

    return $self->error("Incorrect number of arguments. Consult the reference.")
        unless $user && ( scalar(@args) == 0 || scalar(@args) == 2 );

    if ( scalar(@args) == 2 ) {
        my ( $from, $comm ) = @args;
        return $self->error("First argument must be 'from'")
            if $from ne "from";

        $journal = LJ::load_user($comm);
        return $self->error("Unknown account: $comm")
            unless $journal;

        return $self->error("You are not a maintainer of this account")
            unless $remote && $remote->can_manage($journal);
    }

    my $banuser = LJ::load_user($user);
    return $self->error("Unknown account: $user")
        unless $banuser;

    my $banlist = LJ::load_rel_user( $journal, 'B' ) || [];
    return $self->error(
        "You have reached the maximum number of bans.  Unban someone and try again.")
        if scalar(@$banlist) >= ( $LJ::MAX_BANS || 5000 );

    LJ::set_rel( $journal, $banuser, 'B' );
    $journal->log_event( 'ban_set', { actiontarget => $banuser->id, remote => $remote } );

    LJ::Hooks::run_hooks( 'ban_set', $journal, $banuser );

    return $self->print( "User " . $banuser->user . " banned from " . $journal->user );
}

1;
