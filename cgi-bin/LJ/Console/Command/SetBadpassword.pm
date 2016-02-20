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

package LJ::Console::Command::SetBadpassword;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "set_badpassword" }

sub desc { "Mark or unmark an account as having a bad password. Requires priv: suspend." }

sub args_desc { [
                 'user' => "The username of the journal to mark/unmark",
                 'state' => "Either 'on' (to mark as having a bad password) or 'off' (to unmark)",
                 'reason' => "Reason why you are setting this status.",
                 ] }

sub usage { '<user> <state> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "suspend" );
}

sub execute {
    my ($self, $user, $state, $reason, @args) = @_;

    return $self->error("This command takes three arguments. Consult the reference.")
        unless $user && $state && $reason && scalar(@args) == 0;

    my $u = LJ::load_user($user);
    return $self->error("Invalid user: $user")
        unless $u;

    return $self->error("Cannot set bad password flag for a purged account.")
        if $u->is_expunged;

    return $self->error("Account is not a personal journal.")
        unless $u->is_person;

    return $self->error("Second argument must be 'on' or 'off'.")
        unless $state =~ /^(?:on|off)/;
    my $on = ($state eq "on") ? 1 : 0;

    return $self->error("User is already marked as having a bad password.")
        if $on && $u->prop('badpassword');
    return $self->error("User is already marked as not having a bad password.")
        if !$on && !$u->prop('badpassword');

    my $msg;
    if ($on) {
        $u->set_prop('badpassword', 1)
            or return $self->error("Unable to set prop");
        $self->info("User marked as having a bad password.");
        $msg = "marked; $reason";
    } else {
        $u->set_prop('badpassword', 0);

        # set_prop returns the value, so we can't "or" these together
        return $self->error("Unable to set prop") unless !$u->prop('badpassword');

        $self->info("User no longer marked as having a bad password.");
        $msg = "unmarked; $reason";
    }

    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, "set_badpassword", $msg);

    # run the hook
    my $hres = LJ::Hooks::run_hook("set_badpassword", {
        'user'   => $u,
        'on'     => $on,
        'reason' => $reason,
    });

    $self->error("Running of hook failed!")
        if $on && !$hres && LJ::Hooks::are_hooks( 'set_badpassword' );

    return 1;
}

1;
