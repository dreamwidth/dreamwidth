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

package LJ::Console::Command::BanList;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "ban_list" }

sub desc { "Lists users who are banned from an account. Requires priv: none." }

sub args_desc {
    [ 'user' =>
"Optional; lists bans in a community you maintain, or any user if you have the 'finduser' priv."
    ]
}

sub usage { '[ "from" <user> ]' }

sub can_execute { 1 }

sub execute {
    my ( $self, @args ) = @_;
    my $remote  = LJ::get_remote();
    my $journal = $remote;            # may be overridden later

    return $self->error("Incorrect number of arguments. Consult the reference.")
        unless scalar(@args) == 0 || scalar(@args) == 2;

    if ( scalar(@args) == 2 ) {
        my ( $from, $user ) = @args;

        return $self->error("First argument must be 'from'")
            if $from ne "from";

        $journal = LJ::load_user($user);
        return $self->error("Unknown account: $user")
            unless $journal;

        return $self->error("You are not a maintainer of this account")
            unless $remote
            && ( $remote->can_manage($journal)
            || $remote->has_priv("finduser") );
    }

    my $banids   = LJ::load_rel_user( $journal, 'B' ) || [];
    my $us       = LJ::load_userids(@$banids);
    my @userlist = map { $us->{$_}{user} } keys %$us;

    return $self->info( $journal->user . " has not banned any other users." )
        unless @userlist;

    $self->info($_) foreach @userlist;

    return 1;
}

1;
