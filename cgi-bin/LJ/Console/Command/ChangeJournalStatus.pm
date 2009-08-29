package LJ::Console::Command::ChangeJournalStatus;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "change_journal_status" }

sub desc { "Change the status of an account." }

sub args_desc { [
                 'account' => "The account to update.",
                 'status' => "One of 'normal', 'memorial' (no new entries), 'locked' (no new entries or comments), or 'readonly' (no new entries or comments, but can log in and delete entries and comments), 'deleted'.",
                 ] }

sub usage { '<account> <status>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "siteadmin", "users" );
}

sub execute {
    my ($self, $user, $status, @args) = @_;

    return $self->error("This command takes exactly two arguments. Consult the reference")
        unless $user && $status && scalar(@args) == 0;

    my $u = LJ::load_user($user);
    return $self->error("Invalid username: $user")
        unless $u;

    return $self->error("Cannot modify status of a purged journal.")
        if $u->is_expunged;

    # if you add new statusvis - add it to the list of setters below
    my $statusvis = { 'normal' => 'V', 'locked' => 'L', 'memorial' => 'M', 'readonly' => 'O', 'deleted' => 'D', }->{$status};
    return $self->error("Invalid status. Consult the reference.")
        unless $statusvis;

    return $self->error("Account is already in that state.")
        if $u->statusvis eq $statusvis;

    # update statushistory first so we have the old statusvis
    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, "journal_status", "Changed status to $status from " . $u->statusvis);

    # we cannot call set_statusvis directly - it does not make all needed hooks, only sets statusvis
    # so call set_* method
    if ($statusvis eq 'V') {
        $u->set_visible;
    } elsif ($statusvis eq 'L') {
        $u->set_locked;
    } elsif ($statusvis eq 'M') {
        $u->set_memorial;
    } elsif ($statusvis eq 'O') {
        $u->set_readonly;
    } elsif ($statusvis eq 'D') {
        $u->set_deleted;
    } else {
        die "No call to setter for $statusvis case";
    }

    return $self->print("Account has been marked as $status");
}

1;
