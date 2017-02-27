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
use DW::API::Param;
use DW::API::Method;
use JSON;
use Data::Dumper;

use Carp qw/ croak /;

our %API_DOCS = ();
our %TYPE_REGEX = (
    string => '([^/]*)',
    integer => '(\d*)',
    boolean => '(true|false)',
);

# Usage: DW::Controller::API::REST->register_rest_endpoints( $endpoint , $ver );
#
# Registers default GET, POST, PUT, and DELETE handlers for 
# /api/v$ver/$endpoint as well as /api/v$ver/$endpoint/($id)
sub register_rest_controller {
    my ( $self, $info ) = @_;
    my $path = $info->{path}{name};
    my $parameters = $info->{path}{params};
    my $ver = $info->{ver};

    $API_DOCS{$ver}{$self} = $info;
    # check path parameters to make sure they're defined in the API docs
    # substitute appropriate regex if they are
    my @params = ( $path =~ /{([\w\d]+)}/g );

    foreach my $param (@params) {
        croak "Parameter $param is not defined." unless exists $parameters->{$param};
        my $type = $parameters->{$param}->{type};

        if ($parameters->{$param}->{required}) {
            $path =~ s/{$param}/$TYPE_REGEX{$type}/;
        } else {
            $path =~ s/\/{$param}/\/?$TYPE_REGEX{$type}/;
        }

    }

    warn("register rest controller for $path using $self ");

    DW::Routing->register_api_rest_endpoint( $path . '$', "_dispatcher", $info, version => $ver);
}

sub _dispatcher {

    my ( $self, @args ) = @_;

    warn Dumper(%API_DOCS);
    
    warn(" running REST _item_dispatcher; self = " . $self );
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;
    
    my $r = $rv->{r};
    my $method = $r->method;
    my $handler = $self->{path}{methods}->{$method}->{handler};

    #$self->validate_params($method, @args);

    if (defined $handler) {
        return $handler->($self, @args);
    } else {
        return $self->_rest_unimplemented($method);
    }
}
     
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
    my $self = shift;
    my $status_code = shift;
    my $message = scalar @_ >= 2 ?
        sprintf( shift, @_ ) : 'Unknown error.';

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
    $r->print( to_json( $response, { convert_blessed => 1 } ) );
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

    } elsif ( $type eq 'DW::API::Param') {

        # If our argument is a Param, push it 
        # onto the list of path parameters
        $self->{path}{params}{$arg->{name}} = $arg;
    }
}


}

sub param {
    my ($self, $args) = @_;
    my $param = DW::API::Param::define_parameter($args);
    return $param;
}

# helper functions for creating new Method objects
# and adding them to a resource path.

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

# Usage: validate_params(resource object, HTTP verb, arguments)
# Validates path parameters so that handler routines don't have to.
# FIXME: assumes all params are path params right now - we need to add query params

sub validate_params {
    my ($self, $action, @args) = @_;
    my $path = $self->{path}{name};
    my $parameters = $self->{path}{params};

    my @required;
    for my $param (keys %$parameters) {
        push @required, $param if $parameters->{$param}->{required};
    }

    return $self->rest_error(400, "Missing required path argument") if scalar @required > scalar @args;

    my @params = ( $path =~ /{([\w\d]+)}/g );
    foreach (@args) {
        return $self->rest_error(400, "Too many path arguments supplied!") unless exists $params[$_];
        my $type = $parameters->{$params[$_]}->{type};
        my @type_check =grep( /$TYPE_REGEX{$type}/, $args[$_]);

        return $self->rest_error(400, "Argument %s is not of type, should be a %s", ($args[$_], $type)) unless @type_check && $type_check[0] != '';
    }

    return;

}

1;
