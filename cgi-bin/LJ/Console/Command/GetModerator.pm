package LJ::Console::Command::GetModerator;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "get_moderator" }

sub desc { "Given a community username, lists all moderators. Given a user account, lists all communities that the user moderates." }

sub args_desc { [
                 'user' => "The username of the account you want to look up.",
                 ] }

sub usage { '<user>' }

sub can_execute {
    my $remote = LJ::get_remote();
    return $remote && $remote->has_priv( "finduser" );
}

sub execute {
    my ($self, $user, @args) = @_;

    return $self->error("This command takes exactly one argument. Consult the reference.")
        unless $user && scalar(@args) == 0;

    my $relation = LJ::Console::Command::GetRelation->new( command => 'get_maintainer', args => [ $user, 'M' ] );
    $relation->execute($relation->args);
    $self->add_responses($relation->responses);

    return 1;
}

1;
