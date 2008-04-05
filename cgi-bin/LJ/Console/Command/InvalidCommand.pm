package LJ::Console::Command::InvalidCommand;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "invalid command" } # deliberately invalid (space) so people can't actually call this directly

sub desc { "This specifies the console's behavior for invalid input." }

sub args_desc { [] }

sub usage { '' }

sub can_execute { 1 }

sub is_hidden { 1 }

sub execute {
    my ($self, @args) = @_;

    return $self->error("There is no such command '" . LJ::ehtml($self->{command}) . "'.");
}

sub as_string {
    my $self = shift;
    my $ret = join(" ", $self->{command}, $self->args);
    return LJ::ehtml($ret);
}

sub as_html {
    my $self = shift;

    my $out = "<table border='1' cellpadding='5'><tr>";
    $out .= "<td><strong>" . LJ::ehtml($self->{command}) . "</strong></td>";
    $out .= "<td>" . LJ::ehtml($_) . "</td>" foreach $self->args;
    $out .= "</tr></table>";

    return $out;
}

1;
