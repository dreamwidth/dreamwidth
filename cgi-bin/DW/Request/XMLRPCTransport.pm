#!/usr/bin/perl
#
# DW::Request::XMLRPCTransport
#
# XMLRPC transport that supports DW::Request
#
# Authors:
#      SOAP::Lite Authors
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# Based on SOAP::Transport:HTTP, XMLRPC::Transport::HTTP
#    Copyright (C) 2000-2004 Paul Kulchenko (paulclinger@yahoo.com)
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
package DW::Request::XMLRPCTransport;
use strict;
use SOAP::Lite;
use SOAP::Transport::HTTP;
use XMLRPC::Lite;
use XMLRPC::Transport::HTTP;
use HTTP::Request;
use HTTP::Headers;

our @ISA = qw(SOAP::Transport::HTTP::Server);

sub DESTROY { SOAP::Trace::objects('()') }

sub initialize;
*initialize = \&XMLRPC::Server::initialize;
sub make_fault;
*make_fault = \&XMLRPC::Transport::HTTP::CGI::make_fault;
sub make_response;
*make_response = \&XMLRPC::Transport::HTTP::CGI::make_response;

sub new {
    my $self = shift;
    unless ( ref $self ) {
        my $class = ref($self) || $self;
        $self = $class->SUPER::new(@_);
        SOAP::Trace::objects('()');
    }

    return $self;
}

sub handler {
    my $self = shift->new;
    my $r    = DW::Request->get;

    my $req = HTTP::Request->new(
        $r->method => $r->uri,
        HTTP::Headers->new( $r->headers_in ),
        $r->content
    );
    $self->request($req);

    $self->SUPER::handle;

    $r->status_line( $self->response->code );

    $self->response->headers->scan( sub { $r->header_out(@_) } );
    $r->content_type( join '; ', $self->response->content_type );

    $r->print( $self->response->content );

    return $self;
}

sub configure {
    my $self   = shift->new;
    my $config = shift->dir_config;
    for (%$config) {
        $config->{$_} =~ /=>/
            ? $self->$_( { split /\s*(?:=>|,)\s*/, $config->{$_} } )
            : ref $self->$_() ? ()    # hm, nothing can be done here
            : $self->$_( split /\s+|\s*,\s*/, $config->{$_} )
            if $self->can($_);
    }
    return $self;
}

{

    # just create alias
    sub handle;
    *handle = \&handler
}

