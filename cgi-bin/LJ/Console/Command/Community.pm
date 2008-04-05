package LJ::Console::Command::Community;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "community" }

sub desc { "Add or remove a user from a community." }

sub args_desc { [
                 'community' => "The username of the community.",
                 'action' => "Only 'remove' is supported right now.",
                 'user' => "The user you want to remove from the community.",
                 ] }

sub usage { '<community> <action> <user>' }

sub can_execute { 1 }

sub execute {
    my ($self, $commname, $action, $user, @args) = @_;
    my $remote = LJ::get_remote();

    return $self->error("This command takes exactly three arguments. Consult the reference")
        unless $commname && $action && $user && scalar(@args) == 0;

    my $comm = LJ::load_user($commname);
    my $target = LJ::load_user($user);

    return $self->error("Adding users to communities with the console is disabled.")
        if $action eq 'add';

    return $self->error("Unknown action: only 'remove' is currently supported.")
        unless $action eq 'remove';

    return $self->error("Unknown community: $commname")
        unless $comm && $comm->is_community;

    return $self->error("Unknown user: $user")
        unless $target;

    my $can_add = LJ::can_manage($remote, $comm) || LJ::check_priv($remote, "sharedjournal", "*");
    my $can_remove = $can_add || LJ::u_equals($remote, $target);

    return $self->error("You cannot add users to this community.")
        if $action eq 'add' && !$can_add;

    return $self->error("You cannot remove users from this community.")
        if $action eq 'remove' && !$can_remove;

    # since adds are blocked, at this point we know we're removing the user
    LJ::leave_community($target, $comm);
    return $self->print("User " . $target->user . " removed from " . $comm->user);
}

1;
