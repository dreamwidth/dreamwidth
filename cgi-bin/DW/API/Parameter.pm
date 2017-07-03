#!/usr/bin/perl
#
# DW::API::Parameter
#
# Defines Parameter objects and provides helper functions
# for use in DW::Controller::API::REST resources.
#
# Authors:
#      Ruth Hatch <ruth.s.hatch@gmail.com>
#
# Copyright (c) 2017 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::API::Parameter;

use strict;
use warnings;
use JSON;

use Carp qw(croak);

my @ATTRIBUTES = qw(name type in desc);
my @LOCATIONS = qw(path formData body header query);

# Usage: define_parameter ( \%args ) where arg keys are
# name, desc, in, type, or required. Creates and returns
# a new parameter object for use in DW::Controller::API::REST
# resource definitions.

sub define_parameter {
    my $args = $_[0];
    my %parameter = (
        name => $args->{name},
        desc => $args->{description},
        in => $args->{in},
        type => $args->{type},
        required => $args->{required}
    );
    bless \%parameter;
    return \%parameter;
}

# Usage: validate ( Parameter object ) 
# Does some simple validation checks for parameter objects
# Makes sure required fields are present, and that the 
# location given is a valid one.

sub validate {
    my $self = $_[0];
    for my $field (@ATTRIBUTES) {
        die "$self is missing required field $field" unless defined $self->{field};
    }
    my $location = $self->{in};
    die "$location isn't a valid parameter location" unless grep($location, @LOCATIONS);

    return;
}

# Formatter method for the JSON package to output parameter objects as JSON.

sub TO_JSON {
    my $self = $_[0];

    my $json = {
            name => $self->{name},
            description => $self->{desc},
            type => $self->{type},
            in => $self->{in}
    };
        $json->{required} = $JSON::true if defined $self->{required} && $self->{required};
    return $json;

}

1;

