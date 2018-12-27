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
use JSON::Validator 'validate_json';

use Carp qw(croak);

my @ATTRIBUTES = qw(name type in desc);
my @LOCATIONS = qw(path formData body header query);

# Usage: define_parameter ( \%args ) where arg keys are
# name, desc, in, type, or required. Creates and returns
# a new parameter object for use in DW::Controller::API::REST
# resource definitions.

sub define_parameter {
    my ( $class, $args ) = @_;
    my $parameter = {
        name => $args->{name},
        desc => $args->{description},
        in => $args->{in},
        required => $args->{required},
        schema => $args->{schema},
    };
    return bless $parameter, $class;
}

# Usage: validate ( Parameter object ) 
# Does some simple validation checks for parameter objects
# Makes sure required fields are present, and that the 
# location given is a valid one.

sub validate {
    my $self = $_[0];
    for my $field (@ATTRIBUTES) {
        croak "$self is missing required field $field" unless defined $self->{$field};
    }
    my $location = $self->{in};
    croak "$location isn't a valid parameter location" unless grep($location, @LOCATIONS);

    if (defined $self->{schema}) {
        # Make sure we've been provided a valid schema to validate against
        my @errors = validate_json($self->{schema}, 'http://json-schema.org/draft-04/schema#');
        croak "Invalid schema!" if @errors;

        # make a validator against the schema
        my $validator = JSON::Validator->new->schema($self->{schema});
        $self->{validator} = $validator;
    }

    return;
}

# Formatter method for the JSON package to output parameter objects as JSON.

sub TO_JSON {
    my $self = $_[0];

    my $json = {
        name => $self->{name},
        description => $self->{desc},
        in => $self->{in},
        schema => $self->{schema},
    };
        $json->{required} = $JSON::true if defined $self->{required} && $self->{required};
    return $json;

}

1;

