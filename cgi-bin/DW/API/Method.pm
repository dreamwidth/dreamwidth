#!/usr/bin/perl
#
# DW::API::Method
#
# Defines Method objects and provides helper functions
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

package DW::API::Method;

use strict;
use warnings;
use JSON;

use DW::API::Parameter;

my @ATTRIBUTES = qw(name desc handler responses);
my @HTTP_VERBS = qw(GET POST DELETE PUT);

# Usage: define_method ( action, desc, handler ) 
# Creates and returns a new method object for use
# in DW::Controller::API::REST resource definitions.

sub define_method {
    my ($action, $handler, $desc, $summary) = @_;

    my %method = (
        name => $action,
        summary => $summary,
        desc => $desc,
        handler => $handler,
        tags => [], 
        responses => {},
        );

    bless \%method;
    return \%method;
}

# Usage: param ( @args ) 
# Creates a new DW::API::Parameter object and
# adds it to the parameters hash of the calling
# method object

sub param {
    my ($self, @args) = @_;

    my $param = DW::API::Parameter::define_parameter(@args);
    my $name = $param->{name};
    $self->{params}{$name} = $param;
}

# Usage: success ( desc, schema ) 
# Adds a 200 response description and optional schema
# to the responses hash of the calling method object
# FIXME: In the future, we may want 'successes' that aren't
# 200 responses. This will need to be changed accordingly.

sub success {
    my ($self, $desc, $schema) = @_;

    $self->{responses}{200} = { desc => $desc, schema => $schema};
}

# Usage: error ( code, desc ) 
# Adds an error response status code and 
# to the responses hash of the calling method object
# FIXME: Register a sprintf string to use as well?

sub response {
    my ($self, $code, $desc) = @_;

    $self->{responses}{$code} = { desc => $desc };
}

# Usage: _validate ( Method object ) 
# Does some simple validation checks for method objects
# Makes sure required fields are present, and that the 
# HTTP action is a valid one.

sub _validate {
    my $self = $_[0];

    for my $field (@ATTRIBUTES) {
        die "$self is missing required field $field" unless defined $self->{field};
    }
    my $action = $self->{name};
    die "$action isn't a valid HTTP action" unless grep($action, @HTTP_VERBS);

    return;

}

# Formatter method for the JSON package to output method objects as JSON.

sub TO_JSON {
    my $self = $_[0];

    my $json = { description => $self->{desc} };

    if (defined $self->{params}) {
        $json->{parameters} =  [ values $self->{params} ];
    }

    my $responses = $self->{responses};

    for my $key (keys $self->{responses}) {
        $json->{responses}{$key} = { description => $responses->{$key}{desc} };
        $json->{responses}{$key}{schema} = $responses->{$key}{schema} if defined $responses->{$key}{schema};
    }

    return $json;
}


1;

