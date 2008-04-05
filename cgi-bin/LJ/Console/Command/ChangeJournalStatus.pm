package LJ::Console::Command::ChangeJournalStatus;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "change_journal_status" }

sub desc { "Change the status of an account." }

sub args_desc { [
                 'account' => "The account to update.",
                 'status' => "One of 'normal', 'memorial' (no new entries), 'locked' (no new entries or comments), or 'deleted'.",
                 ] }

sub usage { '<account> <status>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "siteadmin", "users");
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

    my $statusvis = { 'normal' => 'V', 'locked' => 'L', 'memorial' => 'M', 'deleted' => 'D', }->{$status};
    return $self->error("Invalid status. Consult the reference.")
        unless $statusvis;

    return $self->error("Account is already in that state.")
        if $u->statusvis eq $statusvis;

    # update statushistory first so we have the old statusvis
    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, "journal_status", "Changed status to $status from " . $u->statusvis);
    $u->set_statusvis($statusvis);

    return $self->print("Account has been marked as $status");
}

1;
