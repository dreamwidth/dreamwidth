package LJ::Console::Command::Print;

use strict;
use base qw(LJ::Console::Command);
use Carp qw(croak);

sub cmd { "print" }

sub desc { "This is a debugging function. Given any number of arguments, it'll print each one back to you. If an argument begins with a bang (!), then it'll be printed to the error stream instead." }

sub args_desc { [] }

sub usage { '...' }

sub requires_remote { 0 }

sub can_execute { 1 }

sub execute {
    my ($self, @args) = @_;

    $self->info("Welcome to 'print'!");

    foreach my $arg (@args) {
        if ($arg =~ /^\!/) {
            $self->error($arg);
        } else {
            $self->print($arg);
        }
    }

    return 1;
}

1;
