# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

# Base class for LJ::Console commands

package LJ::Console::Command;

use strict;
use Carp qw(croak);
use LJ::Console::Response;

sub new {
    my $class = shift;
    my %opts = @_;

    my $self = {
        command => delete $opts{command},
        args    => delete $opts{args} || [],
        output  => [ ],
    };

    # args can be arrayref, or just one arg
    if ($self->{args} && ! ref $self->{args}) {
        $self->{args} = [ $self->{args} ];
    }
    croak "invalid argument: args"
        if $self->{args} && ! ref $self->{args} eq 'ARRAY';

    croak "invalid parameters: ", join(",", keys %opts)
        if %opts;

    return bless $self, $class;
}

sub args {
    my $self = shift;
    return @{$self->{args} || []};
}

## *command = \&cmd is invalid, since derived clases don't
## override method 'command', invocation of $derived->command
## leads to call of Base::cmd() not Derived::cmd()
sub command {
    my $self = shift;
    $self->cmd(@_);
}

sub cmd {
    my $self = shift;
    die "cmd not implemented in $self";
}

sub desc {
    my $self = shift;
    return "";
}

sub usage {
    my $self = shift;
    return "";
}

sub args_desc {
    my $self = shift;

    # [ arg1 => 'desc', arg2 => 'desc' ]
    return [];
}

sub can_execute {
    my $self = shift;
    return 0;
}

sub requires_remote {
    my $self = shift;
    return 1;
}

# hide from console documentation?
sub is_hidden {
    my $self = shift;
    return 0;
}

sub as_string {
    my $self = shift;
    my $ret = join(" ", $self->cmd, $self->args);
    return LJ::ehtml($ret);
}

sub as_html {
    my $self = shift;

    my $out = "<table class='console_command' summary='' border='1' cellpadding='5'><tr>";
    $out .= "<td><strong>" . LJ::ehtml($self->cmd) . "</strong></td>";
    $out .= "<td>" . LJ::ehtml($_) . "</td>" foreach $self->args;
    $out .= "</tr></table>";

    return $out;
}


# return 1 on success.  on failure, return 0 or die.  (will be caught)
sub execute {
    my $self = shift;
    die "execute not implemented in $self";
}

sub execute_safely {
    my $cmd = shift;
    my $remote = LJ::get_remote();

    eval {
        return $cmd->error("You must be logged in to run this command.")
            if $cmd->requires_remote && !$remote;

        return $cmd->error("Your account status prevents you from using the console.")
            if $cmd->requires_remote && !$remote->is_visible;

        return $cmd->error("You are not authorized to run this command.")
            unless $cmd->can_execute;

        my $rv = $cmd->execute($cmd->args);
        return $cmd->error("Command " . $cmd->command . "' didn't execute successfully.")
            unless $rv;
    };

    if ($@) {
        return $cmd->error("Died executing '" . $cmd->command . "': $@");
    }

    return 1;
}

sub responses {
    my $self = shift;
    return @{$self->{output} || []};
}

sub add_responses {
    my $self = shift;
    my @responses = @_;

    push @{$self->{output}}, @responses;
}

sub print {
    my $self = shift;
    my $text = shift;

    push @{$self->{output}}, LJ::Console::Response->new( status => 'success', text => $text );

    return 1;
}

sub error {
    my $self = shift;
    my $text = shift;

    push @{$self->{output}}, LJ::Console::Response->new( status => 'error', text => $text );

    return 1;
}

sub info {
    my $self = shift;
    my $text = shift;

    push @{$self->{output}}, LJ::Console::Response->new( status => 'info', text => $text );

    return 1;
}

1;
