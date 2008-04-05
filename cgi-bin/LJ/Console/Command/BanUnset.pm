package LJ::Console::Command::BanUnset;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "ban_unset" }

sub desc { "Remove a ban on a user." }

sub args_desc { [
                 'user' => "The user you want to unban.",
                 'community' => "Optional; to unban a user from a community you maintain.",
               ] }

sub usage { '<user> [ "from" <community> ]' }

sub can_execute { 1 }

sub execute {
    my ($self, $user, @args) = @_;
    my $remote = LJ::get_remote();
    my $journal = $remote;         # may be overridden later

    return $self->error("Incorrect number of arguments. Consult the reference.")
        unless $user && (scalar(@args) == 0 || scalar(@args) == 2);

    if (scalar(@args) == 2) {
        my ($from, $comm) = @args;
        return $self->error("First argument must be 'from'")
            if $from ne "from";

        $journal = LJ::load_user($comm);
        return $self->error("Unknown account: $comm")
            unless $journal;

        return $self->error("You are not a maintainer of this account")
            unless LJ::can_manage($remote, $journal);
    }

    my $banuser = LJ::load_user($user);
    return $self->error("Unknown account: $user")
        unless $banuser;

    LJ::clear_rel($journal, $banuser, 'B');
    $journal->log_event('ban_unset', { actiontarget => $banuser->id, remote => $remote });

    return $self->print("User " . $banuser->user . " unbanned from " . $journal->user);
}

1;
