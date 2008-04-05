package LJ::Console::Command::GetRelation;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "get_relation" }

sub desc { "Given a username and an edge, looks up all relations." }

sub args_desc { [
                 'user' => "The username of the account you want to look up.",
                 'edge' => "The reluser edge to look up.",
                 ] }

sub usage { '<user> <edge>' }

sub can_execute { 0 }  # can't be called directly

sub is_hidden { 1 }

sub execute {
    my ($self, $user, $edge, @args) = @_;

    return $self->error("This command takes exactly two arguments. Consult the reference.")
        unless $user && $edge && scalar(@args) == 0;

    my $u = LJ::load_user($user);
    return $self->error("Invalid user $user")
        unless $u;

    my $ids = $u->is_person ? LJ::load_rel_target($u, $edge) : LJ::load_rel_user($u, $edge);
    my $us = LJ::load_userids(@{$ids || []});

    foreach my $u (sort { $a->id <=> $b->id } values %$us) {
        next unless $u;
        my $finduser = LJ::Console::Command::Finduser->new( command => 'finduser', args => [ 'timeupdate', $u->user ] );
        $finduser->execute($finduser->args);
        $self->add_responses($finduser->responses);
    }

    return 1;
}

1;
