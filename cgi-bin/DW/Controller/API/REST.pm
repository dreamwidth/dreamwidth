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
use JSON;

use Carp qw/ croak /;

# Usage: DW::Controller::API::REST->register_rest_endpoints( $endpoint , $ver );
#
# Registers default GET, POST, PUT, and DELETE handlers for 
# /api/v$ver/$endpoint as well as /api/v$ver/$endpoint/($id)
sub register_rest_endpoints {
    my ( $self, $endpoint, $handler, $ver ) = @_;

    warn("registering endpoints for $endpoint using handler $handler ");
    DW::Routing->register_api_regex_endpoints(
        [ $endpoint . '$',   $handler, $ver ],
        [ $endpoint . '/([^/]*)$', $handler, $ver ],
        );
}

# Usage: DW::Controller::API::REST->register_rest_endpoints( $endpoint , $ver );
#
# Registers default GET, POST, PUT, and DELETE handlers for 
# /api/v$ver/$endpoint as well as /api/v$ver/$endpoint/($id)
sub register_rest_controller {
    my ( $self, $endpoint, $ver ) = @_;

    warn("register rest controller for $endpoint using $self ");
    DW::Routing->register_api_rest_endpoints( 
        [ $endpoint . '$', "_list_dispatcher", $self, $ver ],
        [ $endpoint . '/([^/]*)$', "_item_dispatcher", $self, $ver ],
        );
}

sub _item_dispatcher {
    my ( $self, @args ) = @_;
    
    warn(" running REST _item_dispatcher; self = " . $self );
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;
    
    my $r = $rv->{r};
    if ( $r->method eq 'GET' ) {
        return $self->rest_get_item( @args );
    } elsif ( $r->method eq 'POST' ) {
        return $self->rest_post_item( @args );
    } elsif ( $r->method eq 'PUT' ) {
        return $self->rest_put_item( @args );
    } elsif ( $r->method eq 'DELETE' ) {
        return $self->rest_delete_item( @args );
    } else {
        return $self->_rest_unimplemented();
    }
}
    
sub _list_dispatcher {
    my ( $self, @args ) = @_;
    
    warn(" running REST _list_dispatcher; self = " . $self );
    my ( $ok, $rv ) = controller( anonymous => 1 );
    return $rv unless $ok;
    
    my $r = $rv->{r};
    if ( $r->method eq 'GET' ) {
        return $self->rest_get_list( @args );
    } elsif ( $r->method eq 'POST' ) {
        return $self->rest_post_list( @args );
    } elsif ( $r->method eq 'PUT' ) {
        return $self->rest_put_list( @args );
    } elsif ( $r->method eq 'DELETE' ) {
        return $self->rest_delete_list( @args );
    } else {
        return $self->_rest_unimplemented();
    }
}
    
sub rest_get_list {
    my $self = $_[0];
    warn( "default get list; self=" . $self ); 
    return _rest_unimplemented( "GET" );
}

sub rest_post_list {
    return _rest_unimplemented( "POST" );
}
sub rest_put_list {
    return _rest_unimplemented( "PUT" );
}
sub rest_delete_list {
    return _rest_unimplemented( "DELETE" );
}
 
sub rest_get_item {
    my $self = $_[0];
    warn( "default get item; self=" . $self ); 
    return _rest_unimplemented( "GET" );
}

sub rest_post_item {
    return _rest_unimplemented( "POST" );
}
sub rest_put_item {
    return _rest_unimplemented( "PUT" );
}
sub rest_delete_item {
    return _rest_unimplemented( "DELETE" );
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


1;
