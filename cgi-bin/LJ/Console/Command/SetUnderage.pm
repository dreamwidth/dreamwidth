package LJ::Console::Command::SetUnderage;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "set_underage" }

sub desc { "Change an account's underage status." }

sub args_desc { [
                 'user' => "The username of the journal to mark/unmark",
                 'state' => "Either 'on' (to mark as being underage) or 'off' (to unmark)",
                 'reason' => "Required information about why you are setting this status.",
                 ] }

sub usage { '<user> <state> <reason>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "siteadmin", "underage");
}

sub execute {
    my ($self, $user, $state, $reason, @args) = @_;

    return $self->error("This command takes three arguments. Consult the reference.")
        unless $user && $state && $reason && scalar(@args) == 0;

    my $u = LJ::load_user($user);
    return $self->error("Invalid user: $user")
        unless $u;
    return $self->error("Account is not a personal account.")
        unless $u->is_person;

    return $self->error("Second argument must be 'on' or 'off'.")
        unless $state =~ /^(?:on|off)/;
    my $on = ($state eq "on") ? 1 : 0;

    return $self->error("User is already marked as underage.")
        if $on && $u->underage;
    return $self->error("User is not currently marked as underage.")
        if !$on && !$u->underage;

    my ($status, $msg);
    if ($on) {
        $status = 'M'; # "M"anually turned on
        $self->print("User marked as underage.");
        $msg = "marked; $reason";
    } else {
        $status = undef; # no status change
        $self->print("User no longer marked as underage.");
        $msg = "unmarked; $reason";
    }

    # now record this change (yes, we log it twice)
    my $remote = LJ::get_remote();
    LJ::statushistory_add($u, $remote, "set_underage", $msg);
    $u->underage($on, $status, "manual");

    return 1;
}

1;
