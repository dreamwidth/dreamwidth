# Simple object to represent console responses

package LJ::Console::Response;

use strict;
use Carp qw(croak);

sub new {
    my $class = shift;
    my %opts  = @_;

    my $self = {
        status => delete $opts{status},
        text   => delete $opts{text},
    };

    croak "invalid parameter: status"
        unless $self->{status} =~ /^(?:info|success|error)$/;

    croak "invalid parameters: ", join(",", keys %opts)
        if %opts;

    return bless $self, $class;
}

sub status {
    my $self = shift;
    return $self->{status};
}

sub text {
    my $self = shift;
    return $self->{text};
}

sub is_success {
    my $self = shift;
    return $self->status eq 'success' ? 1 : 0;
}

sub is_error {
    my $self = shift;
    return $self->status eq 'error' ? 1 : 0;
}

sub is_info {
    my $self = shift;
    return $self->status eq 'info' ? 1 : 0;
}

sub as_string {
    my $self = shift;
    return join(": ", $self->status, $self->text);
}

sub as_html {
    my $self = shift;

    my $color;
    if ($self->is_error) {
        $color = "#FF0000";
    } elsif ($self->is_success) {
        $color = "#008800";
    } else {
        $color = "#000000";
    }

    return "<span style='color:$color;'>" . LJ::eall($self->text) . "</span>";
}

1;
