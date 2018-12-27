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
use JSON::Validator 'validate_json';
use Carp qw/ croak /;

use DW::API::Parameter;
use DW::Request;

my @ATTRIBUTES = qw(name desc handler responses);
my @HTTP_VERBS = qw(GET POST DELETE PUT);

# Usage: define_method ( action, desc, handler ) 
# Creates and returns a new method object for use
# in DW::Controller::API::REST resource definitions.

sub define_method {
    my ($class, $action, $handler, $config) = @_;

    my $method = {
        name => $action,
        summary => $config->{summary},
        desc => $config->{description},
        handler => $handler,
        tags => [], 
        responses => {},
        };

    bless $method, $class;
    $method->_responses($config->{responses});
    return $method;
}

# Usage: param ( @args ) 
# Creates a new DW::API::Parameter object and
# adds it to the parameters hash of the calling
# method object

sub param {
    my ($self, @args) = @_;

    my $param = DW::API::Parameter->define_parameter(@args);
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

sub _responses {
    my ($self, $resp_config) = @_;

    # add response descriptions
        for my $code (keys %$resp_config) {
            my $desc = $resp_config->{$code}->{description};
            $self->{responses}{$code} = { desc => $desc };

            # for every content type we provide as response, see if we have a valid schema
            for my $content_type (keys %{$resp_config->{$code}->{content}}) {
                my $content = $resp_config->{$code}->{content}->{$content_type};
                if (defined $content->{schema}) {
                    # Make sure we've been provided a valid schema to validate against
                    my @errors = validate_json($content->{schema}, 'http://json-schema.org/draft-07/schema#');
                    die "Invalid schema! Errors: @errors" if @errors;

                    # make a validator against the schema
                    my $validator = JSON::Validator->new->schema($content->{schema});
                    $content->{validator} = $validator;
                }
                 $self->{responses}{$code}{content}->{$content_type} = $content;
            }

        }
}

# Usage: _validate ( Method object ) 
# Does some simple validation checks for method objects
# Makes sure required fields are present, and that the 
# HTTP action is a valid one.

sub _validate {
    my $self = $_[0];

    for my $field (@ATTRIBUTES) {
        die "$self is missing required field $field" unless defined $self->{$field};
    }
    my $action = $self->{name};
    die "$action isn't a valid HTTP action" unless grep($action, @HTTP_VERBS);

    return;

}

# Usage: return rest_ok( response, content-type )
# takes a scalar or scalar ref to a response object, and an
# optional content-type - default is JSON if not specified.
# Returns the response object with the given content type.
sub rest_ok {
    croak 'too many arguments to api_ok!'
        unless scalar @_ <= 3;
    
    my ( $self, $response, $content_type ) = @_;
    my $r = DW::Request->get;

    $content_type = defined $content_type ? $content_type : 'application/json';
    my $validator = $self->{responses}{200}{content}{$content_type}{validator};

    # guarantee that we're returning what we say we return.
    if (defined $validator) {
        my @errors = $validator->validate($response);
        if (@errors) {
            croak "Invalid response format! Validator errors: @errors";
        }
    }

    $r->print( to_json( $response, { convert_blessed => 1 , pretty => 1} ) );
    $r->status( 200 );
    return;
}

# Usage: return rest_error( $r->STATUS_CODE_CONSTANT,
#                          'format/message', [arg, arg, arg...] )
# Returns a standard format JSON error message.
# The first argument is the status code
# The second argument is a string that might be a format string:
# it's passed to sprintf with the rest of the
# arguments.
sub rest_error {
    my ($self, $status_code, @args) = @_;
    my $status_desc = $self->{responses}{$status_code}{desc};
    my $message = defined $status_desc ?
        sprintf( $status_desc ) : 'Unknown error.';

    my $res = {
        success => 0,
        error   => $message,
    };

    my $r = DW::Request->get;
    $r->print( to_json( $res ) );
    $r->status( $status_code );
    return;
}


# Formatter method for the JSON package to output method objects as JSON.

sub TO_JSON {
    my $self = $_[0];

    my $json = { description => $self->{desc} };

    if (defined $self->{params}) {
        $json->{parameters} =  [ values %{$self->{params}} ];
    }

    my $responses = $self->{responses};

    for my $key (keys %{$self->{responses}}) {
        $json->{responses}{$key} = { description => $responses->{$key}{desc} };
        $json->{responses}{$key}{schema} = $responses->{$key}{schema} if defined $responses->{$key}{schema};
    }

    return $json;
}


1;

