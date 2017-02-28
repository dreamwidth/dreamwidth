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
use JSON;

use Carp qw/ croak /;

our %API_DOCS = ();
our %TYPE_REGEX = (
    string => '([^/]*)',
    integer => '(\d*)',
    boolean => '(true|false)',
);

# Usage: DW::Controller::API::REST->register_rest_endpoints( $resource , $ver );
#
# Validates given API resource object's route path, substitutes parameters with
# their regex representation, and then registers that path in the routing table
# with the generic handler _dispatcher and the defining resoure object. Adds
# the resource object to the %API_DOCS hash for building our API documentation.

sub register_rest_controller {
    my ( $self, $info ) = @_;
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
    my $method = $r->method;
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
#    my @allowed = $self->get_allowed_methods($controller, $c, $method_name);
#    $c->response->content_type('text/plain');
#    $c->response->status(405);
#    $c->response->header( 'Allow' => \@allowed );
#    $c->response->body( "Method "
#          . $c->request->method
#          . " not implemented for "
#          . $c->uri_for( $method_name ) );
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

# Usage: resource( path => path, ver => version #)
# Creates a new REST API resource object with given path
# and version number.
sub resource { 
     my ($self, %args) = @_;
     my %resource = (
        path => {
            name => $args{path},
            },
        ver => $args{ver},
        );

     bless(\%resource, $self);
     return \%resource;
}

# helper function for registering new descriptors or
# path parameters.

sub path {
    my ($self, @args) = @_;

    for my $arg (@args) {
    my $type = ref $arg;


    # if our argument is a hash ref, we move
    # it's keys and values into the path hash
    if ( $type eq 'HASH') {
        for my $key (keys %$arg) {
        $self->{path}{$key} = $arg->{$key};
        }

    } elsif ( $type eq 'DW::API::Parameter') {

        # If our argument is a Param, push it 
        # onto the list of path parameters
        $self->{path}{params}{$arg->{name}} = $arg;
    }
}


}

# Usage: resource->param(\%args)
# A wrapper around DW::API::Parameter::define_parameter,
# to make it a little nicer to define new ones in API
# resoure files.
sub param {
    my ($self, $args) = @_;
    my $param = DW::API::Parameter::define_parameter($args);
    return $param;
}

# Usage: resource->method($desc)
# helper functions for creating new Method objects
# and adding them to the methods hash of a resource object.

sub get {
    my ($self, @args) = @_;
        my $method = DW::API::Method::define_method('GET', @args);
        $self->{path}{methods}{GET} = $method;
}

sub post {
    my ($self, @args) = @_;
        my $method = define_method('POST', @args);
        $self->{path}{methods}{POST} = $method;
}

sub delete {
    my ($self, @args) = @_;
        my $method = DW::API::Method::define_method('DELETE', @args);
        $self->{path}{methods}{DELETE} = $method;
}

sub put {
    my ($self, @args) = @_;
        my $method = DW::API::Method::define_method('PUT', @args);
        $self->{path}{methods}{PUT} = $method;
}

# Formatter method for the JSON package to output resource objects as JSON.


sub TO_JSON {
    my $self = $_[0];

    my $json = {};
    if (defined $self->{path}{params}) {
        $json->{parameters} = [ values $self->{path}{params} ];
    }

        for my $key (keys $self->{path}{methods}) {
            $json->{lc $key} = $self->{path}{methods}{$key};
        }
    return $json;
}

1;
