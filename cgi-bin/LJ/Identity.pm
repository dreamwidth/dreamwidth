package LJ::Identity;

use strict;

use fields (
            'typeid',  # Id number of identity type
            'value',   # Identity string
            );

sub new {
    my LJ::Identity $self = shift;
    $self = fields::new( $self ) unless ref $self;
    my %opts = @_;

    $self->{typeid} = $opts{'typeid'};
    $self->{value}  = $opts{'value'};

    return $self;
}

sub pretty_type {
    my LJ::Identity $self = shift;
    return 'OpenID' if $self->{typeid} == 0;
    return 'Invalid identity type';
}

sub typeid {
    my LJ::Identity $self = shift;
    die("Cannot set new typeid value") if @_;

    return $self->{typeid};
}

sub value {
    my LJ::Identity $self = shift;
    die("Cannot set new identity value") if @_;

    return $self->{value};
}
1;
