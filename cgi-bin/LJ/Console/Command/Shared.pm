package LJ::Console::Command::Shared;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "shared" }

sub desc { "Add or remove posting access in a shared journal." }

sub args_desc { [
                 'sharedjournal' => "The username of the shared journal.",
                 'action' => "Either 'add' or 'remove'.",
                 'user' => "The user you want to add or remove from posting in the shared journal.",
                 ] }

sub usage { '<sharedjournal> <action> <user>' }

sub can_execute { 1 }

sub execute {
    my ($self, $shared_user, $action, $target_user, @args) = @_;

    return $self->error("This command takes exactly three arguments. Consult the reference.")
        unless $shared_user && $action && $target_user && scalar(@args) == 0;

    my $shared = LJ::load_user($shared_user);
    my $target = LJ::load_user($target_user);

    return $self->error("Invalid shared journal $shared_user")
        unless $shared && $shared->is_shared;

    return $self->error("Invalid user $target_user")
        unless $target && $target->is_person;

    my $remote = LJ::get_remote();
    return $self->error("You don't have access to manage this shared journal.")
        unless LJ::can_manage($remote, $shared) || LJ::check_priv($remote, "sharedjournal", "*");

    if ($action eq "add") {
        return $self->error("User $target_user already has posting access to this shared journal.")
            if LJ::check_rel($shared, $target, 'P');

        # don't send request if the admin is giving themselves posting access
        if (LJ::u_equals($target, $remote)) {
            LJ::set_rel($shared, $target, 'P');
            return $self->print("User $target_user has been given posting access to $shared_user.");
        } else {
            my $res = LJ::shared_member_request($shared, $target);
            return $self->error("Could not add user.")
                unless $res;

            return $self->error("User $target_user already invited to join on: $res->{'datecreate'}")
                if $res->{'datecreate'};

            return $self->print("User $target_user has been sent a confirmation email, and will be able to post "
                                  . "in $shared_user when they confirm this action.");
        }

    } elsif ($action eq "remove") {
        LJ::clear_rel($shared, $target, 'P');
        return $self->print("User $target_user can no longer post in $shared_user.");

    } else {
        return $self->error("Invalid action. Must be either 'add' or 'remove'.");
    }

}

1;
