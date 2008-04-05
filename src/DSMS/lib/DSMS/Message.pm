#!/usr/bin/perl

# DSMS Message object
#
# internal fields:
#
#    to:         arrayref of MSISDNs of msg recipients
#    from:       shortcode from which the message is being sent
#    uniq_key:   optional unique identifier of remote gateway
#    subject:    text subject for message
#    body_text:  decoded text body of message
#    body_raw:   raw text body of message
#    type:       'incoming' or 'outgoing'
#    meta:       hashref of metadata key/value pairs
#    

package DSMS::Message;

use strict;
use Carp qw(croak);
use Class::Autouse qw(Encode);

sub new {
    my $class = shift;
    my $self  = {};

    my %args  = @_;

    foreach (qw(to from uniq_key subject body_text body_raw type meta)) {
        $self->{$_} = delete $args{$_};
    }
    croak "invalid parameters: " . join(",", keys %args)
        if %args;


    # FIXME: should a lot of this checking be moved
    #        to the DSMS::Provider's ->send method?

    {
        croak "no from address specified"
            unless $self->{from};

        croak "no recipients specified"
            unless $self->{to};

        if (ref $self->{to}) {
            croak "to arguments must be scalar or arrayref"
                if ref $self->{to} ne 'ARRAY';
        } else {
            $self->{to} = [ $self->{to} ];
        }
        croak "empty recipient list"
            unless scalar @{$self->{to}};

        foreach my $msisdn (@{$self->{to}}, $self->{from}) {
            $msisdn =~ s/[\s\-]+//g;
            croak "invalid recipient: $msisdn"
                unless $msisdn =~ /^\+?\d+$/;
        }

        croak "invalid type argument"
            unless $self->{type} =~ /^(?:incoming|outgoing)$/;

        croak "invalid meta argument"
            if $self->{meta} && ref $self->{meta} ne 'HASH';

        $self->{meta} ||= {};
    }

    # FIXME: length requirements?
    $self->{subject}   .= '';
    $self->{body_text} .= '';
    $self->{body_raw} = $self->{body_text} unless defined $self->{body_raw};

    return bless $self;
}

# generic getter/setter
sub _get {
    my DSMS::Message $self = shift;
    my ($f, $v) = @_;
    croak "invalid field: $f" 
        unless exists $self->{$f};

    return $self->{$f} = $v if defined $v;
    return $self->{$f};
}

sub encode_utf8 {
    my DSMS::Message $self = shift;

    # encode top level members
    foreach my $member (keys %$self) {
        next if $member eq 'meta';
        next if $member eq 'to';
        $self->{$member} = Encode::encode_utf8($self->{$member});
    }

    # 'to' is an arrayref of msisdns
    foreach my $msisdn (@{$self->{to}}) {
        $msisdn = Encode::encode_utf8($msisdn);
    }

    # encode metadata in hashref
    if (ref $self->{meta}) {
        my $meta = $self->{meta};
        foreach my $prop (keys %$meta) {
            $meta->{$prop} = Encode::encode_utf8($meta->{$prop});
        }
    }

    # utf8 flags are now off!
    return 1;
}

# handy function for debugging
sub dump_utf8_status {
    my DSMS::Message $self = shift;

    foreach my $member (keys %$self) {
        next if $member eq 'meta';
        next if $member eq 'to';
        warn "$member=$self->{$member}, flag=" . (Encode::is_utf8($self->{$member})) . "\n";
    }

    # 'to' is an arrayref of msisdns
    foreach my $msisdn (@{$self->{to}}) {
        warn "to=$msisdn, flag=" . (Encode::is_utf8($msisdn)) . "\n";
    }

    if (ref $self->{meta}) {
        my $meta = $self->{meta};
        foreach my $prop (keys %$meta) {
            warn "$prop=$meta->{$prop}, flag=" . (Encode::is_utf8($meta->{$prop})) . "\n";
        }
    }
}

sub to        { _get($_[0], 'to',        $_[1]) }
sub from      { _get($_[0], 'from',      $_[1]) }
sub uniq_key  { _get($_[0], 'uniq_key',  $_[1]) }
sub subject   { _get($_[0], 'subject',   $_[1]) }
sub body_text { _get($_[0], 'body_text', $_[1]) }
sub body_raw  { _get($_[0], 'body_raw',  $_[1]) }
sub type      { _get($_[0], 'type',      $_[1]) }

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

sub is_incoming {
    my DSMS::Message $self = shift;
    return $self->type eq 'incoming' ? 1 : 0;
}

sub is_outgoing {
    my DSMS::Message $self = shift;
    return $self->type eq 'outgoing' ? 1 : 0;
}

1;
