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

my @REQ_ATTRIBUTES = qw(name in desc);
my @OPT_ATTRIBUTES = qw(required example examples style schema content);
my @LOCATIONS      = qw(path cookie header query requestBody);

# Usage: define_parameter ( \%args ) where arg keys are
# name, desc, in, type, or required. Creates and returns
# a new parameter object for use in DW::Controller::API::REST
# resource definitions.

sub define_parameter {
    my ( $class, $args ) = @_;
    my $parameter = {
        name     => $args->{name},
        desc     => $args->{description},
        in       => $args->{in},
        required => $args->{required},
    };

    if ( defined $args->{schema} ) {
        $parameter->{schema} = $args->{schema};
    }
    elsif ( defined $args->{content} ) {
        $parameter->{content} = $args->{content};
    }

    bless $parameter, $class;
    $parameter->_validate;
    return $parameter;

}

# Usage: validate ( Parameter object )
# Does some simple validation checks for parameter objects
# Makes sure required fields are present, and that the
# location given is a valid one.

sub _validate {
    my $self = $_[0];
    for my $field (@REQ_ATTRIBUTES) {
        croak "$self is missing required field $field" unless defined $self->{$field};
    }
    my $location = $self->{in};
    croak "$location isn't a valid parameter location" unless grep( $location, @LOCATIONS );

    my $has_schema  = defined( $self->{schema} );
    my $has_content = defined( $self->{content} );

    croak "Can only define one of content or schema!" if $has_schema && $has_content;
    croak "Must define at least one of content or schema!" unless $has_content || $has_schema;

    # requestBody is a special instance of Parameter and has stricter rules
    if ( $location eq "requestBody" ) {
        if ( not defined( keys %{ $self->{content} } ) ) {
            croak "requestBody must have at least one content-type!";
        }
    }

    # Run schema validators
    DW::Controller::API::REST::schema($self) if ( defined $self->{schema} );

    if ( defined $self->{content} ) {
        for my $content_type ( keys %{ $self->{content} } ) {
            DW::Controller::API::REST::schema( $self->{content}->{$content_type} );
        }
    }
    return;
}

# Formatter method for the JSON package to output parameter objects as JSON.

sub TO_JSON {
    my $self = $_[0];

    my $json = {
        name        => $self->{name},
        description => $self->{desc},
        in          => $self->{in},
    };

    if ( defined $self->{schema} ) {
        $json->{schema} = $self->{schema};
    }
    elsif ( defined $self->{content} ) {
        $json->{content} = $self->{content};

        # content type is just a hash, but we don't want to print the validator too
        for my $content_type ( keys %{ $json->{content} } ) {
            delete $json->{content}->{$content_type}{validator};
        }
    }

    $json->{required} = $JSON::true if defined $self->{required} && $self->{required};
    return $json;

}

1;

