package LJ::Console::Command::FindUserCluster;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "find_user_cluster" }

sub desc { "List the name of the cluster a user is on." }

sub args_desc { [
                 'user' => "Username of the account to look up",
                 ] }

sub usage { '<user>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return LJ::check_priv($remote, "supportviewscreened") || LJ::check_priv($remote, "supporthelp");
}

sub execute {
    my ($self, $user, @args) = @_;

    return $self->error("This command takes one argument. Consult the reference.")
        unless $user && scalar(@args) == 0;

    my $u = LJ::load_user($user);
    return $self->error("Invalid username $user")
        unless $u;

    my $cluster = LJ::get_cluster_description($u->{clusterid}, 0);
    return $self->print("$user is on the $cluster cluster");
}

1;
