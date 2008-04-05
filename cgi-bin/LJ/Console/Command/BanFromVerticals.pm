package LJ::Console::Command::BanFromVerticals;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "ban_from_verticals" }

sub desc { "Prevent a user from appearing in entry aggregations (verticals) throughout the site." }

sub args_desc { [
                 'user'   => "The username of the account",
                 'state'  => "Either 'on' (to remove from displays) or 'off' (to include)",
                 'reason' => "Reason why the action is being done.",
                 ] }

sub usage { '<user> <state> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "admin", "vertical");
}

sub execute {
    my ($self, $user, $state, $reason, @args) = @_;

    return $self->error("This command takes three arguments. Consult the reference.")
        unless $user && $state && $reason && scalar(@args) == 0;

    my $u = LJ::load_user($user);
    return $self->error("Invalid user: $user")
        unless $u;

    return $self->error("Second argument must be 'on' or 'off'.")
        unless $state =~ /^(?:on|off)/;
    my $on = ($state eq "on") ? 1 : 0;

    return $self->error("User is already blocked from appearing in verticals.")
        if $on && $u->prop("exclude_from_verticals");
    return $self->error("User is not blocked from appearing in verticals.")
        if !$on && !$u->prop("exclude_from_verticals");

    my $msg;
    if ($on) {
        $u->set_prop("exclude_from_verticals", 1);
        $self->print($u->user . " will no longer appear in verticals.");
        $msg = "flagged";
    } else {
        $u->clear_prop("exclude_from_verticals");
        $self->print($u->user . " will now appear in verticals.");
        $msg = "unflagged";
    }

    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, "ban_from_verticals", $msg . "; " . $reason);

    return 1;
}

1;
