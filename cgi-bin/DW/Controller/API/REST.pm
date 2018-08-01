#!/usr/bin/perl
#
# DW::Controller::API::REST
#
# 
#
# Authors:
#      Allen Petersen <allen@suberic.net>
#
# Copyright (c) 2016 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::API::REST;

use strict;
use warnings;
use DW::Request;
use DW::Routing;
use DW::Controller;
use DW::Controller::API;
use DW::API::Parameter;
use DW::API::Method;
use DW::API::Key;
use JSON;
use YAML::XS qw'LoadFile';

use Carp qw/ croak /;

our %API_DOCS = ();
our %TYPE_REGEX = (
    string => '([^/]*)',
    integer => '(\d*)',
    boolean => '(true|false)',
);
our %METHODS = (get => 1, post => 1, delete => 1);
our $API_PATH = "$ENV{LJHOME}/api/";

# Usage: path ( yaml_source_path, ver, hash_of_HTTP_handlers ) 
# Creates a new path object for use in DW::Controller::API::REST 
#resource definitions from a OpenAPI-compliant YAML file and handler sub references

sub path {
    my ($class, $source, $ver, $handlers) = @_;

    my $config = LoadFile($API_PATH . $source);

    my $route = {
        ver => $ver};

    my $path;
    for my $key (keys $config->{paths}) {
        $route->{'path'}{'name'} = $key;
        $path = $key;
    }

    bless $route, $class;

    if (exists $config->{paths}->{$path}->{parameters}) {
        for my $param (@{$config->{paths}->{$path}->{parameters}}) {
            my $new_param = DW::API::Parameter->define_parameter($param);
            $route->{path}{params}{$param->{name}} = $new_param;
            }
        delete $config->{paths}->{$path}->{parameters};
    }

    for my $method (keys $config->{paths}->{$path}) {
        # make sure that it's a valid HTTP method, and we have a handler for it
        die "$method isn't a valid HTTP method" unless $METHODS{$method};
        die "No handler sub was passed for $method" unless $handlers->{$method};

        my $method_config = $config->{paths}->{$path}->{$method};
        $route->_add_method($method, $handlers->{$method}, $method_config);

    }
    register_rest_controller($route);
    return $route;
}

sub _add_method {
    my ($self, $method, $handler, $config) = @_;
        my $new_method = DW::API::Method->define_method($method, $handler, $config->{description}, $config->{summary});

        # add method params
        if (exists $config->{parameters}){
            for my $param (@{$config->{parameters}}) {
                $new_method->param($param);
            }
        }

        # add response descriptions
        for my $response (keys %{$config->{responses}}) {
            my $desc = $config->{responses}->{$response}->{description};
            $new_method->response($response, $desc);
        }


    $self->{path}->{methods}->{$method} = $new_method;

}


# Usage: DW::Controller::API::REST->register_rest_endpoints( $resource , $ver );
#
# Validates given API resource object's route path, substitutes parameters with
# their regex representation, and then registers that path in the routing table
# with the generic handler _dispatcher and the defining resoure object. Adds
# the resource object to the %API_DOCS hash for building our API documentation.

sub register_rest_controller {
    my ( $info ) = shift;
    my $path = $info->{path}{name};
    my $parameters = $info->{path}{params};
    my $ver = $info->{ver};

    $API_DOCS{$ver}{$path} = $info;
    # check path parameters to make sure they're defined in the API docs
    # substitute appropriate regex if they are
    my @params = ( $path =~ /{([\w\d]+)}/g );

    foreach my $param (@params) {
        die "Parameter $param is not defined." unless exists $parameters->{$param};
        my $type = $parameters->{$param}->{type};
        $path =~ s/{$param}/$TYPE_REGEX{$type}/;
        
        }


    DW::Routing->register_api_rest_endpoint( $path . '$', "_dispatcher", $info, version => $ver);
}

# A generic API method dispatcher, for use in registering API
# endpoints to the routing table. When called, looks up the handler
# defined in the resource object for that HTTP action and calls it
# or returns an error response if it's not implemented.

sub _dispatcher {

    my ( $self, @args ) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;
    
    my $r = $rv->{r};
    my $apikey = DW::API::Key->get_key($r->header_in('api_key'));

    unless ($apikey) {
        $r->print( to_json({ success => 0, error => "Missing or invalid API key"}) );
        $r->status( '401' );
        return;
    }

    my $method = lc $r->method;
    my $handler = $self->{path}{methods}->{$method}->{handler};

    if (defined $handler) {
        return $handler->($self, @args);
    } else {
        return $self->_rest_unimplemented($method);
    }
}

# Generic response handler for unimplemented API methods.
     
sub _rest_unimplemented {

    return api_error( { error => $_[0] . " Not Implemented"  } );
}

# Usage: return rest_error( $r->STATUS_CODE_CONSTANT,
#                          'format/message', [arg, arg, arg...] )
# Returns a standard format JSON error message.
# The first argument is the status code
# The second argument is a string that might be a format string:
# it's passed to sprintf with the rest of the
# arguments.
sub rest_error {
    my ($self, $action, $status_code, @args) = @_;
    my $status_desc = $self->{path}{methods}{$action}->{responses}{$status_code}{desc};
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

# Usage: return api_ok( SCALAR )
# Takes a scalar as input, then constructs an output JSON object. The output
# object is always of the format:
#   { success => 0/1, result => SCALAR }
# SCALAR can of course be a hashref, arrayref, or value.
sub rest_ok {
    croak 'api_ok takes one argument only'
        unless scalar @_ == 2;
    
    my ( $self, $response ) = @_;


    my $r = DW::Request->get;
    $r->print( to_json( $response, { convert_blessed => 1 , pretty => 1} ) );
    $r->status( 200 );
    return;
}


# Formatter method for the JSON package to output resource objects as JSON.


sub TO_JSON {
    my $self = $_[0];

    my $json = {};
    if (defined $self->{path}{params}) {
        $json->{parameters} = [ values %{$self->{path}{params}} ];
    }

        for my $key (keys %{$self->{path}{methods}}) {
            $json->{lc $key} = $self->{path}{methods}{$key};
        }
    return $json;
}

1;
