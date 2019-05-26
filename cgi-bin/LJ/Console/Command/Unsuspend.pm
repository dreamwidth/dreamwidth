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

package LJ::Console::Command::Unsuspend;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "unsuspend" }

sub desc { "Unsuspend an account or entry. Requires priv: suspend." }

sub args_desc {
    [
        'username or email address or entry url' =>
"The username of the account to unsuspend, or an email address to unsuspend all accounts at that address, or an entry URL to unsuspend a single entry within an account",
        'reason' => "Why you're unsuspending the account or entry",
    ]
}

sub usage { '<username or email address or entry url> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv("suspend");
}

sub execute {
    my ( $self, $user, $reason, $confirmed, @args ) = @_;

    return $self->error("This command takes two arguments. Consult the reference.")
        unless $user && $reason && scalar(@args) == 0;

    my $remote = LJ::get_remote();
    my $entry  = LJ::Entry->new_from_url($user);
    if ($entry) {
        my $poster  = $entry->poster;
        my $journal = $entry->journal;

        return $self->error("Invalid entry.")
            unless $entry->valid;

        return $self->error("Journal and/or poster is purged; cannot unsuspend entry.")
            if $poster->is_expunged || $journal->is_expunged;

        return $self->error("Entry is not currently suspended.")
            if $entry->is_visible;

        $entry->set_prop( statusvis           => "V" );
        $entry->set_prop( unsuspend_supportid => 0 )
            if $entry->prop("unsuspend_supportid");

        $reason = "entry: " . $entry->url . "; reason: $reason";
        LJ::statushistory_add( $journal, $remote, "unsuspend", $reason );
        LJ::statushistory_add( $poster,  $remote, "unsuspend", $reason )
            unless $journal->equals($poster);

        return $self->print( "Entry " . $entry->url . " unsuspended." );
    }

    my @users;
    if ( $user !~ /@/ ) {
        push @users, $user;

    }
    else {
        $self->info("Acting on users matching email $user");

        my @userids = LJ::User->accounts_by_email($user);
        return $self->error("No users found matching the email address $user.")
            unless @userids;

        my $us = LJ::load_userids(@userids);

        foreach my $u ( values %$us ) {
            push @users, $u->user;
        }

        unless ( $confirmed eq "confirm" ) {
            $self->info("   $_") foreach @users;
            $self->info("To actually confirm this action, please do this again:");
            $self->info("   unsuspend $user \"$reason\" confirm");
            return 1;
        }
    }

    foreach my $username (@users) {
        my $u = LJ::load_user($username);

        unless ($u) {
            $self->error("Unable to load '$username'");
            next;
        }

        unless ( $u->is_suspended ) {
            $self->error("$username is not currently suspended; skipping.");
            next;
        }

        $u->update_self( { statusvis => 'V', raw => 'statusvisdate=NOW()' } );
        $u->{statusvis} = 'V';

        LJ::statushistory_add( $u, $remote, "unsuspend", $reason );

        $self->print("User '$username' unsuspended.");
    }

    return 1;
}

1;
