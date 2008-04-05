#!/usr/bin/perl

# DSMS Gateway object
#
# internal fields:
#
#    config     hashref of config key/value pairs
#    

package DSMS::Gateway;

use strict;
use Carp qw(croak);

sub new {
    my $class = shift;
    my $self  = {};

    my %args  = @_;

    foreach (qw(config)) {
        $self->{$_} = delete $args{$_};
    }
    croak "invalid parameters: " . join(",", keys %args)
        if %args;

    # $self->{config} is opaque

    return bless $self, $class;
}

sub config {
    my $self = shift;
    croak "config is an object method"
        unless ref $self;

    my $key = shift;
    croak "no config key specified for retrieval"
        unless length $key;

    die "config key '$key' does not exist"
        unless exists $self->{config}->{$key};

    return $self->{config}->{$key};
}

sub send_msg {
    my $self = shift;
    croak "send_msg is an object method"
        unless ref $self;

    my $msg = shift;
    croak "invalid message to send"
        unless $msg && $msg->isa("DSMS::Message");

    my %opts = @_;
    my $verify_delivery = delete $opts{verify_delivery};
    croak "invalid opts parameters for DSMS::Gateway::Mobile365: " .
        join(",", keys %opts) if %opts;

    warn "DUMMY: send_msg";

    return 1;
}

sub recv_msg_http {
    my $self = shift;
    croak "recv_sms_http is an object method"
        unless ref $self;

    my $r = shift;
    croak "recv_msg_http received an invalid Apache 'r' object"
        unless ref $r;

    warn "DUMMY: recv_msg_http";

    return 1;
}

sub recv_msg {
    my $self = shift;
    croak "recv_sms is an object method"
        unless ref $self;

    warn "DUMMY: recv_msg";

    return 1;
}

sub recv_ack_http {
    my $self = shift;
    croak "recv_ack_http is an object method"
        unless ref $self;

    my $r = shift;
    croak "recv_ack_http received an invalid Apache 'r' object"
        unless ref $r;

    warn "DUMMY: recv_ack_http";

    return 1;
}

sub recv_ack {
    my $self = shift;
    croak "recv_ack is an object method"
        unless ref $self;

    warn "DUMMY: recv_ack";

    return 1;
}

sub final_byte_length {
    my $class = shift;

    my $text = shift;
    return length($text);
}

# TODO: recv_msg_* ?

1;
