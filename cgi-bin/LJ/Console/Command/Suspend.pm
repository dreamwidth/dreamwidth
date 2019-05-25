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

package LJ::Console::Command::Suspend;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "suspend" }

sub desc { "Suspend an account or entry. Requires priv: suspend." }

sub args_desc {
    [
        'username or email address or entry url' =>
"The username of the account to suspend, or an email address to suspend all accounts at that address, or an entry URL to suspend a single entry within an account",
        'reason' => "Why you're suspending the account or entry.",
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
    my $openid_only =
        $remote->has_priv( "suspend", "openid" ) && !$remote->has_priv( "suspend", "*" );

    my $entry = LJ::Entry->new_from_url($user);
    if ($entry) {
        my $poster  = $entry->poster;
        my $journal = $entry->journal;

        return $self->error("You are not authorized to suspend entries.")
            if $openid_only;

        return $self->error("Invalid entry.")
            unless $entry->valid;

        return $self->error("Entry is already suspended.")
            if $entry->is_suspended;

        $entry->set_prop( statusvis => "S" );

        $reason = "entry: " . $entry->url . "; reason: $reason";
        LJ::statushistory_add( $journal, $remote, "suspend", $reason );
        LJ::statushistory_add( $poster,  $remote, "suspend", $reason )
            unless $journal->equals($poster);

        return $self->print( "Entry " . $entry->url . " suspended." );
    }

    my @users;
    if ( $user !~ /@/ ) {
        push @users, $user;

    }
    else {

        return $self->error("You are not authorized to suspend by email address.")
            if $openid_only;

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
            $self->info("   suspend $user \"$reason\" confirm");
            return 1;
        }
    }

    foreach my $username (@users) {
        my $u = LJ::load_user($username);

        unless ($u) {
            $self->error("Unable to load '$username'");
            next;
        }

        if ( $u->is_expunged ) {
            $self->error("$username is purged; skipping.");
            next;
        }

        if ( $u->is_suspended ) {
            $self->error("$username is already suspended.");
            next;
        }

        if ( $openid_only && !$u->is_identity ) {
            $self->error("$username is not an identity account.");
            next;
        }

        if ( $u->get_suspend_note && $confirmed ne "confirm" ) {
            $self->error("One or more accounts have suspend notes:");
            $self->error( "   " . $u->get_suspend_note ) foreach @users;
            $self->error("To actually confirm this action, please do this again:");
            $self->error("   suspend $user \"$reason\" confirm");
            next;
        }

        my $err;
        $self->error($err)
            unless $u->set_suspended( $remote, $reason, \$err );

        $self->print("User '$username' suspended.");
    }

    return 1;
}

1;
