#!/usr/bin/perl

# DSMS MessageAck object
#
# internal fields:
#
#    msisdn:      MSISDN for which ack was received
#    msg_uniq:    unique identifier of message being ack'd
#    type:        ack type: 'gateway', 'smsc', 'handset', 'unknown'
#    timestamp:   unixtime when ack was received
#    status_flag: status classification: 'success', 'error', 'unknown'
#    status_code: optional status code given with ack (0x1234)
#    status_text: full text of status given for ack
#    meta:        hashref of metadata key/value pairs

package DSMS::MessageAck;

use strict;
use Carp qw(croak);
use Class::Autouse qw(Encode);

sub new {
    my $class = shift;
    my $self  = {};

    my %args  = @_;

    foreach (qw(msisdn msg_uniq type timestamp status_flag status_code status_text meta)) {
        $self->{$_} = delete $args{$_};
    }
    croak "invalid parameters: " . join(",", keys %args)
        if %args;

    $self->{msisdn} =~ s/[\s\-]+//g;
    croak "invalid recipient: $self->{msisdn}"
        if $self->{msisdn} && $self->{msisdn} !~ /^\+?\d+$/;

    croak "invalid type argument: $self->{type}"
        unless $self->{type} =~ /^(?:gateway|smsc|handset|unknown)$/;

    croak "invalid status_flag argument: $self->{status_flag}"
        unless $self->{status_flag} =~ /^(?:success|error|unknown)$/;

    croak "invalid timestamp argument: $self->{timestamp}"
        unless int($self->{timestamp}) > 0 =~ /^(?:gateway|smsc|handset|unknown)$/;

    croak "invalid meta argument"
        if $self->{meta} && ref $self->{meta} ne 'HASH';

    $self->{meta} ||= {};

    # msg_uniq, status_code, status_text, meta are optional

    return bless $self;
}

# generic getter/setter
sub _get {
    my $self = shift;
    my ($f, $v) = @_;
    croak "invalid field: $f" 
        unless exists $self->{$f};

    return $self->{$f} = $v if defined $v;
    return $self->{$f};
}

sub msisdn      { _get($_[0], 'msisdn',      $_[1]) }
sub msg_uniq    { _get($_[0], 'msg_uniq',    $_[1]) }
sub type        { _get($_[0], 'type',        $_[1]) }
sub timestamp   { _get($_[0], 'timestamp',   $_[1]) }
sub status_flag { _get($_[0], 'status_flag', $_[1]) }
sub status_code { _get($_[0], 'status_code', $_[1]) }
sub status_text { _get($_[0], 'status_text', $_[1]) }

sub meta {
    my $self = shift;
    my $key  = shift;
    my $val  = shift;

    my $meta = $self->{meta} || {};

    # if a value was specified for a set, handle that here
    if ($key && $val) {

        # update elements in memory
        my %to_set = ($key => $val, @_);
        while (my ($k, $v) = each %to_set) {
            $meta->{$k} = $v;
        }

        # return new set value of the first element passed
        return $meta->{$key};
    }

    # if a specific key was specified, return that element
    # ... otherwise return a hashref of all k/v pairs
    return $key ? $meta->{$key} : $meta;
}

sub is_success {
    my $self = shift;
    return $self->status_flag eq 'success' ? 1 : 0;
}

sub is_error {
    my $self = shift;
    return $self->status_flag eq 'error' ? 1 : 0;
}

1;
