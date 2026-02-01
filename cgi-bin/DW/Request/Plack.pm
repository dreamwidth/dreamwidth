#!/usr/bin/perl
#
# DW::Request::Plack
#
# Abstraction layer for using Plack's $env model to power Dreamwidth based
# systems.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2021 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Request::Plack;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use DW::Request::Base;
use base 'DW::Request::Base';

use Plack::Request;
use Plack::Response;
use URI;

use fields ( 'env', 'req', 'req_addr', 'res', 'res_body', 'res_length', 'notes', 'pnotes' );

$DW::Request::PLACK_AVAILABLE = 1;

BEGIN {
    # Do initialization for pass-throughs that will go to the Plack::Request
    # object inside
    foreach my $method (qw/ uri method query_string /) {
        no strict 'refs';
        *{"DW::Request::Plack::$method"} = sub {
            my DW::Request::Plack $self = shift;
            return $self->{req}->$method(@_);
        };
    }
}

# creates a new DW::Request object, based on what type of server environment we
# are running under
sub new {
    my DW::Request::Plack $self = $_[0];
    my $plack_env = $_[1];

    # Create self if needed
    $self = fields::new($self) unless ref $self;
    $self->SUPER::new;

    # Convert PSGI $env to Plack::Request and store for pass-thru usage
    $self->{env}        = $plack_env;
    $self->{req}        = Plack::Request->new($plack_env);
    $self->{req_addr}   = undef;
    $self->{res}        = Plack::Response->new;
    $self->{res_body}   = undef;                             # or scalar
    $self->{res_length} = 0;

    # now stick ourselves as the primary request ...
    unless ($DW::Request::cur_req) {
        $DW::Request::determined = 1;
        $DW::Request::cur_req    = $self;
    }

    return $self;
}

# response methods to update the response we're going to send
sub header_out {
    my DW::Request::Plack $self = $_[0];
    return $self->{res}->header( $_[1] ) if scalar @_ == 2;
    return $self->{res}->header( $_[1] => $_[2] );
}

# In Plack there's no distinction between error and normal headers
*err_header_out = \&header_out;

# _add variants append instead of replacing (needed for Set-Cookie)
sub header_out_add {
    my DW::Request::Plack $self = $_[0];
    $self->{res}->headers->push_header( $_[1] => $_[2] );
}

*err_header_out_add = \&header_out_add;

# incoming headers, from request
sub header_in {
    my DW::Request::Plack $self = $_[0];
    return $self->{req}->header( $_[1] ) if scalar @_ == 2;

    $log->info( 'Set ', $_[1], ' => ', $_[2] );
    return $self->{req}->header( $_[1] => $_[2] );
}

# get client address; allow overriding it because we need to set it in some
# cases when we're dealing with proxies
sub address {
    my DW::Request::Plack $self = $_[0];
    return $self->{req_addr} // $self->{req}->address if scalar @_ == 1;

    $log->info( 'Address set to ', $_[1] );
    return $self->{req_addr} = $_[1];
}

# return host
sub host {
    my DW::Request::Plack $self = $_[0];
    return $self->header_in('Host');
}

# set the status
sub status {
    my DW::Request::Plack $self = $_[0];
    $self->{res}->status( $_[1] ) if defined $_[1];
    return $self->{res}->status;
}

# append to the body
sub print {
    my DW::Request::Plack $self = $_[0];
    push @{ $self->{res_body} ||= [] }, $_[1];
    $self->{res_length} += length( $_[1] );
}

# flatten out the body and return the response
sub res {
    my DW::Request::Plack $self = $_[0];

    if ( defined $self->{res_body} ) {
        $self->{res}->body( $self->{res_body} );
        $self->{res}->content_length( $self->{res_length} );
    }

    return $self->{res}->finalize;
}

# return path
sub path {
    my DW::Request::Plack $self = $_[0];
    return $self->{req}->path;
}

# query parameters
sub query_parameters {
    my DW::Request::Plack $self = $_[0];
    return $self->{req}->query_parameters;
}

# return a new response that is a redirect
sub redirect {
    my DW::Request::Plack $self = $_[0];

    # This is a 303 because we want to be explicit that when we do a redirect we expect
    # the user-agent to switch to a GET; this is an old assumption baked into the LJ/DW
    # code now made explicit here.
    return Plack::Response->new( 303, { 'Location' => $_[1] }, '' )->finalize;
}

# assemble a URL for something
sub uri_for {
    my DW::Request::Plack $self = $_[0];
    my ( $path, $args ) = ( $_[1], $_[2] );

    my $uri = $self->{req}->base;
    $uri->path( $uri->path . $path );
    $uri->query_form(@$args) if %$args;
    return $uri;
}

# content_type: getter reads from request, setter sets on response
sub content_type {
    my DW::Request::Plack $self = $_[0];
    if ( scalar @_ >= 2 ) {
        return $self->{res}->content_type( $_[1] );
    }
    return $self->{req}->content_type;
}

# content: return raw request body
sub content {
    my DW::Request::Plack $self = $_[0];
    return $self->{req}->content;
}

# pnote: per-request notes hash (used by routing)
sub pnote {
    my DW::Request::Plack $self = $_[0];
    if ( scalar(@_) == 2 ) {
        return $self->{pnotes}->{ $_[1] };
    }
    else {
        return $self->{pnotes}->{ $_[1] } = $_[2];
    }
}

# note: per-request notes hash (separate from pnotes)
sub note {
    my DW::Request::Plack $self = $_[0];
    if ( scalar(@_) == 2 ) {
        return $self->{notes}->{ $_[1] };
    }
    else {
        return $self->{notes}->{ $_[1] } = $_[2];
    }
}

# no_cache: set cache-control headers to prevent caching
sub no_cache {
    my DW::Request::Plack $self = $_[0];
    $self->{res}->header( 'Cache-Control' => 'no-cache, no-store, must-revalidate' );
    $self->{res}->header( 'Pragma'        => 'no-cache' );
    $self->{res}->header( 'Expires'       => '0' );
}

# get_remote_ip: return the client IP address
sub get_remote_ip {
    my DW::Request::Plack $self = $_[0];
    return $self->address;
}

# Some things we need to pass to our base class
# *call_response_handler = \&DW::Request::call_response_handler;

1;
