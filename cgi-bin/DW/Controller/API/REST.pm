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
use JSON::Validator 'validate_json';
use Hash::MultiValue;

use Carp qw/ croak /;

our %API_DOCS   = ();
our %TYPE_REGEX = (
    string  => '([^/]+)',
    integer => '(\d+)',
    boolean => '(true|false)',
);
our %METHODS  = ( get => 1, post => 1, delete => 1 );
our $API_PATH = "$ENV{LJHOME}/api/";

# Usage: path ( yaml_source_path, ver, hash_of_HTTP_handlers )
# Creates a new path object for use in DW::Controller::API::REST
#resource definitions from a OpenAPI-compliant YAML file and handler sub references

sub path {
    my ( $class, $source, $ver, $handlers ) = @_;

    my $config = LoadFile( $API_PATH . $source );

    my $route = { ver => $ver };

    my $path;
    for my $key ( keys %{ $config->{paths} } ) {
        $route->{'path'}{'name'} = $key;
        $path = $key;
    }

    bless $route, $class;

    if ( exists $config->{paths}->{$path}->{parameters} ) {
        for my $param ( @{ $config->{paths}->{$path}->{parameters} } ) {
            my $new_param = DW::API::Parameter->define_parameter($param);
            $route->{path}{params}{ $param->{name} } = $new_param;
        }
        delete $config->{paths}->{$path}->{parameters};
    }

    for my $method ( keys %{ $config->{paths}->{$path} } ) {

        # make sure that it's a valid HTTP method, and we have a handler for it
        die "$method isn't a valid HTTP method" unless $METHODS{$method};
        die "No handler sub was passed for $method" unless $handlers->{$method};

        my $method_config = $config->{paths}->{$path}->{$method};
        $route->_add_method( $method, $handlers->{$method}, $method_config );

    }

    register_rest_controller($route);
    return $route;
}

sub _add_method {
    my ( $self, $method, $handler, $config ) = @_;
    my $new_method = DW::API::Method->define_method( $method, $handler, $config );

    # add method params
    if ( exists $config->{parameters} ) {
        for my $param ( @{ $config->{parameters} } ) {
            $new_method->param($param);
        }
    }

    if ( exists $config->{requestBody} ) {
        $new_method->body( $config->{requestBody} );
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
    my ($info) = shift;

    my $path       = $info->{path}{name};
    my $parameters = $info->{path}{params};
    my $ver        = $info->{ver};

    $API_DOCS{$ver}{$path} = $info;

    # check path parameters to make sure they're defined in the API docs
    # substitute appropriate regex if they are
    my @params = ( $path =~ /{([\w\d]+)}/g );

    foreach my $param (@params) {
        die "Parameter $param is not defined." unless exists $parameters->{$param};
        my $type = $parameters->{$param}->{schema}->{type};
        $path =~ s/{$param}/$TYPE_REGEX{$type}/;

    }
    DW::Routing->register_api_rest_endpoint( $path . '$', "_dispatcher", $info, version => $ver );
}

# A generic API method dispatcher, for use in registering API
# endpoints to the routing table. When called, it validates credentials
# and parameters, and if successful, looks up the handler
# defined in the resource object for that HTTP action and calls it
# or returns an error response if it's not implemented.

sub _dispatcher {

    my ( $self, $callinfo, @path_args ) = @_;

    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;

    my $r      = $rv->{r};
    my $keystr = $r->header_in('Authorization');
    $keystr =~ s/Bearer (\w+)/$1/;
    my $apikey = DW::API::Key->get_key($keystr);

# all paths require an API key except the spec (which informs users that they need a key and where to put it)
    unless ( $apikey || $self->{path}{name} eq "/spec" ) {
        $r->print( to_json( { success => 0, error => "Missing or invalid API key" } ) );
        $r->status('401');
        return;
    }

    # match path parameters to their names
    my $path        = $self->{path}{name};
    my $path_params = {};
    my @path_names  = ( $path =~ /{([\w]+)}/g );
    for ( my $i = 0 ; $i < @path_names ; $i++ ) {
        $path_params->{ $path_names[$i] } = $path_args[$i];
    }

    my $args = {};
    $args->{user} = $apikey->{user} if $apikey;

    # check path-level parameters.
    for my $param ( keys %{ $self->{path}{params} } ) {
        _validate_param( $param, $self->{path}{params}{$param}, $r, $path_params, $args );
    }

    my $method      = lc $r->method;
    my $handler     = $self->{path}{methods}->{$method}->{handler};
    my $method_self = $self->{path}{methods}->{$method};

    # check method-level parameters
    for my $param ( keys %{ $method_self->{params} } ) {
        _validate_param( $param, $self->{params}{$param}, $r, $args );
    }

    # if we accept a request body, validate that too.
    if ( defined $method_self->{requestBody} ) {
        _validate_body( $method_self->{requestBody}, $r, $args );
    }

    # some handlers need to know what version they are
    $method_self->{ver} = $self->{ver};

    if ( defined $handler ) {
        return $handler->( $method_self, $args );
    }
    else {
        # Generic response for unimplemented API methods.
        $r->print( to_json( { success => 0, error => "Not Implemented" } ) );
        $r->status('501');
        return;
    }
}

# Usage: _validate_param (param, param config, request, path params, arg object)
# Helper function to provide formatting and validation of parameters
# Will return an error message to user on error, or update the given arg
# hash on success.

# NOTE query/header/cookie params are not well-tested yet
# so if you're trying to implement an api route that uses them
# and weird things are happening, it may be this, not you.

sub _validate_param {
    my ( $param, $config, $r, $path_params, $arg_obj ) = @_;

    my $ploc = $config->{in};
    my $preq = $config->{required};
    my $pval = $config->{validator};
    my $p;

    if ( $ploc eq 'query' ) {
        $p = $r->{get_args}{$param};
    }
    elsif ( $ploc eq 'header' ) {
        $p = $r->header_in($param);
    }
    elsif ( $ploc eq 'cookie' ) {
        $p = $r->cookie($param);
    }
    elsif ( $ploc eq 'path' ) {
        $p = $path_params->{$param};
    }

    # make sure that required parameters are supplied
    if ($preq) {
        unless ( defined $p ) {
            $r->print( to_json( { success => 0, error => "Missing required parameter $param" } ) );
            $r->status('400');
            return;
        }
    }

    # run the schema validator
    my @errors = $pval->validate($p);
    if (@errors) {
        my $err_str = join( ', ', map { $_->{message} } @errors );
        $r->print(
            to_json( { success => 0, error => "Bad format for $param. Errors: $err_str" } ) );
        $r->status('400');
        return;
    }

    $arg_obj->{$ploc}{$param} = $p;
}

# Usage: _validate_body (requestBody config, request, arg object)
# Helper function to provide formatting and validation of request bodies
# Will return an error message to user on error, or update the given arg
# hash on success.

# NOTE requestBody params are not well-tested yet
# so if you're trying to implement an api route that uses them
# and weird things are happening, it may be this, not you.

sub _validate_body {
    my ( $config, $r, $arg_obj ) = @_;

    my $preq         = $config->{required};
    my $content_type = lc $r->header_in('Content-Type');
    my $p;

    if ( $content_type eq 'application/json' ) {
        $p = $r->json;
    }
    elsif ( $content_type eq 'application/x-www-form-urlencoded' ) {
        $p = $r->post_args;
    }
    elsif ( $content_type eq 'multipart/form-data' ) {

        # uploads are an array of hashrefs, so we convert to Hash::MultiValue for simplicty
        my @uploads     = $r->uploads;
        my $upload_hash = Hash::MultiValue->new();
        for my $item (@uploads) {
            $upload_hash->add( $item->{name} => $item->{body} );
        }
        $p = $upload_hash;
    }

    # make sure that required parameters are supplied
    if ($preq) {
        unless ( defined $p ) {
            $r->print(
                to_json( { success => 0, error => "Missing or badly formatted request!" } ) );
            $r->status('400');
            return;
        }
    }

    # run the schema validator
    my @errors = $config->{content}->{$content_type}{validator}->validate($p);
    if (@errors) {
        my $err_str = join( ', ', map { $_->{message} } @errors );
        $r->print(
            to_json( { success => 0, error => "Bad format for request body. Errors: $err_str" } ) );
        $r->status('400');
        return;
    }

    $arg_obj->{body} = $p;
}

# Usage: schema ($object_ref)
# Validates a JSON Schema attached to an object, and adds a validator
# for that schema to the object. Used at multiple levels of API defs,
# which is why it's in this package.
sub schema {
    my ($self) = @_;

    if ( defined $self->{schema} ) {

        # Make sure we've been provided a valid schema to validate against
        my @errors = validate_json( $self->{schema}, 'http://json-schema.org/draft-07/schema#' );
        croak "Invalid schema! Errors: @errors" if @errors;

        # make a validator against the schema
        my $validator = JSON::Validator->new->schema( $self->{schema} );

        # turn on coercion for params, because perl doesn't care about scalar types but JSON does
        # so we're more flexible on input than output
        if ( ref($self) eq 'DW::API::Parameter' ) {
            $validator = $validator->coerce( { 'booleans' => 1, 'numbers' => 1, 'strings' => 1 } );
        }

        $self->{validator} = $validator;
    }
    else {
        croak "No schema defined!";
    }

}

# Formatter method for the JSON package to output resource objects as JSON.

sub TO_JSON {
    my $self = $_[0];

    my $json = {};
    if ( defined $self->{path}{params} ) {
        $json->{parameters} = [ values %{ $self->{path}{params} } ];
    }

    for my $key ( keys %{ $self->{path}{methods} } ) {
        $json->{ lc $key } = $self->{path}{methods}{$key};
    }
    return $json;
}

1;
