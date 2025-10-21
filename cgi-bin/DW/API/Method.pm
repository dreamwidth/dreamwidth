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
use Carp qw/ croak /;

use DW::API::Parameter;
use DW::Request;

my @ATTRIBUTES = qw(name desc handler responses);
my @HTTP_VERBS = qw(GET POST DELETE PUT);

# Usage: define_method ( action, desc, handler )
# Creates and returns a new method object for use
# in DW::Controller::API::REST resource definitions.

sub define_method {
    my ( $class, $action, $handler, $config ) = @_;

    my $method = {
        name      => $action,
        summary   => $config->{summary},
        desc      => $config->{description},
        handler   => $handler,
        tags      => [],
        responses => {},
    };

    bless $method, $class;
    $method->_responses( $config->{responses} );
    return $method;
}

# Usage: param ( @args )
# Creates a new DW::API::Parameter object and
# adds it to the parameters hash of the calling
# method object

sub param {
    my ( $self, @args ) = @_;

    my $param = DW::API::Parameter->define_parameter(@args);
    my $name  = $param->{name};
    $self->{params}{$name} = $param;
}

# Usage: body ( @args )
# Creates a special instance of DW::API::Parameter object and
# adds it as the requestBody definition for the calling method
sub body {
    my ( $self, @args ) = @_;
    my $param = DW::API::Parameter->define_parameter(@args);
    $self->{requestBody} = $param;

}

# Usage: success ( desc, schema )
# Adds a 200 response description and optional schema
# to the responses hash of the calling method object
# FIXME: In the future, we may want 'successes' that aren't
# 200 responses. This will need to be changed accordingly.

# sub success {
#     my ($self, $desc, $schema) = @_;

#     $self->{responses}{200} = { desc => $desc, schema => $schema};
# }

# Usage: _responses ( method, config )
# Registers various response types, and validates any with a schema.

sub _responses {
    my ( $self, $resp_config ) = @_;

    # add response descriptions
    for my $code ( keys %$resp_config ) {
        my $desc = $resp_config->{$code}->{description};
        $self->{responses}{$code} = { desc => $desc };

        # for every content type we provide as response, see if we have a valid schema
        for my $content_type ( keys %{ $resp_config->{$code}->{content} } ) {
            my $content = $resp_config->{$code}->{content}->{$content_type};
            DW::Controller::API::REST::schema($content);
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
    die "$action isn't a valid HTTP action" unless grep( $action, @HTTP_VERBS );

    return;

}

# Usage: return rest_ok( response, content-type, status code )
# takes a scalar or scalar ref to a response, an
# optional content-type, and optional status code - default
# content-type is JSON if not specified, and default status is
# Returns a response object with the given content, content-type,
# and status code.
sub rest_ok {
    croak 'too many arguments to api_ok!'
        unless scalar @_ <= 4;

    my ( $self, $response, $content_type, $status_code ) = @_;
    my $r = DW::Request->get;

    $content_type = defined $content_type ? $content_type : 'application/json';
    $status_code  = defined $status_code  ? $status_code  : 200;
    my $validator = $self->{responses}{$status_code}{content}{$content_type}{validator};

    # guarantee that we're returning what we say we return.
    if ( defined $validator ) {
        my @errors = $validator->validate($response);
        if (@errors) {
            croak "Invalid response format! Validator errors: @errors";
        }
    }

    # if we have JSON, call the formatter to pretty-print it. Otherwise, we assume
    # other content-types have already been properly formatted for us.
    if ( $content_type eq "application/json" ) {
        $r->print( to_json( $response, { convert_blessed => 1, pretty => 1 } ) );
    }
    else {
        $r->print($response);
    }

    $r->status($status_code);
    $r->content_type($content_type);
    return;
}

# Usage: return rest_error( $status_code, $msg )
# Returns a standard format JSON error message.
# The first argument is the status code, the second optional
# argument is an error message to be returned. If no message is
# provided, it will pull from the route configuration instead,
# and if there's no route configuration, will return a generic error.
sub rest_error {
    my ( $self, $status_code, $msg ) = @_;
    my $status_desc = $self->{responses}{$status_code}{desc};
    my $default_msg = defined $status_desc ? $status_desc : 'Unknown error.';
    $msg = defined $msg ? $msg : $default_msg;

    my $res = {
        success => 0,
        error   => $msg,
    };

    my $r = DW::Request->get;
    $r->content_type("application/json");
    $r->print( to_json($res) );
    $r->status($status_code);
    return;
}

# Formatter method for the JSON package to output method objects as JSON.

sub TO_JSON {
    my $self = $_[0];

    my $json = { description => $self->{desc} };

    if ( defined $self->{params} ) {
        $json->{parameters} = [ values %{ $self->{params} } ];
    }

    my $responses = $self->{responses};

    for my $key ( keys %{ $self->{responses} } ) {
        $json->{responses}{$key} = { description => $responses->{$key}{desc} };
        $json->{responses}{$key}{schema} = $responses->{$key}{schema}
            if defined $responses->{$key}{schema};
    }

    return $json;
}

1;

