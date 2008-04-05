#!/usr/bin/perl

# DSMS GatewayResponse object
#
# internal fields:
#
#    msg:        DSMS::Message object, or undef on error
#    is_success: Boolean success value of the response
#    error_str:  Error string if ! is_success
#    responder:  Response content callback
#    

package DSMS::GatewayResponse;

use strict;
use Carp qw(croak);

sub new {
    my $class = shift;
    my $self  = bless {}, $class;

    my %args  = @_;

    foreach my $el (qw(msg is_success error_str responder)) {
        $self->$el(delete $args{$el});
    }

    return $self;
}

sub is_error {
    my $self = shift;
    return ! $self->is_success;
}

sub send_response {
    my $self = shift;

    my $cb = $self->responder;
    die "invalid content callback"
        unless ref $cb eq 'CODE';

    return $cb->();
}

# accessors
sub msg {
    my $self = shift;

    if (@_) {
        my $msg = shift;
        croak "invalid DSMS::Message object"
            if $msg && ! $msg->isa("DSMS::Message");

        return $self->{msg} = $msg;
    }

    return $self->{msg};
}

sub responder  {
    my $self = shift;

    if (@_) {
        my $cb = shift;
        croak "invalid responder callback"
            if $cb && ! ref $cb eq 'CODE';

        return $self->{responder} = $cb;
    }

    return $self->{responder};
}

sub is_success {
    my $self = shift;

    if (@_) {
        my $flag = shift;
        $flag = $flag ? 1 : 0;

        return $self->{is_success} = $flag;
    }

    return $self->{is_success};
}

sub error_str  {
    my $self   = shift;

    if (@_) {
        my $errstr = shift || "";

        # we warn with error strings
        warn $errstr if length $errstr;

        return $self->{error_str} = $errstr;
    }

    return $self->{error_str};
}

1;
