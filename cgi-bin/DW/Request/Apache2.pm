#!/usr/bin/perl
#
# DW::Request::Apache2
#
# Abstraction layer for Apache 2/mod_perl 2.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2008-2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Request::Apache2;
use strict;
use DW::Request::Base;
use base 'DW::Request::Base';

use Apache2::Const -compile => qw/ :common :http /;
use Apache2::Log ();
use Apache2::Request;
use Apache2::Response    ();
use Apache2::RequestRec  ();
use Apache2::RequestUtil ();
use Apache2::RequestIO   ();
use Apache2::SubProcess  ();
use Hash::MultiValue;

use fields (
    'r',    # The Apache2::Request object
);

# creates a new DW::Request object, based on what type of server environment we
# are running under
sub new {
    my DW::Request::Apache2 $self = $_[0];
    $self = fields::new($self) unless ref $self;
    $self->SUPER::new;

    # setup object
    $self->{r} = $_[1];

    # done
    return $self;
}

# current document root
sub document_root {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->document_root;
}

# method string GET, POST, etc
sub method {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->method;
}

# the URI requested (does not include host:port info)
sub uri {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->uri;
}

# This sets the content-type on the response. This is NOT a request method. For
# that, use the header_in method and check Content-Type.
sub content_type {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->content_type( $_[1] );
}

# returns the query string
sub query_string {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->args;
}

# returns the raw content of the body; note that this can be particularly
# slow, so you should only call this if you really need it...
sub content {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{content} if defined $self->{content};

    my $buff = '';
    while ( my $ct = $self->{r}->read( my $buf, 65536 ) ) {
        $buff .= $buf;
        last if $ct < 65536;
    }
    return $self->{content} = $buff;
}

# searches for a given note and returns the value, or sets it
sub note {
    my DW::Request::Apache2 $self = $_[0];
    if ( scalar(@_) == 2 ) {
        return $self->{r}->notes->{ $_[1] };
    }
    else {
        return $self->{r}->notes->{ $_[1] } = $_[2];
    }
}

# searches for a given pnote and returns the value, or sets it
sub pnote {
    my DW::Request::Apache2 $self = $_[0];
    if ( scalar(@_) == 2 ) {
        return $self->{r}->pnotes->{ $_[1] };
    }
    else {
        return $self->{r}->pnotes->{ $_[1] } = $_[2];
    }
}

# searches for a given header and returns the value, or sets it
sub header_in {
    my DW::Request::Apache2 $self = $_[0];
    if ( scalar(@_) == 2 ) {
        return $self->{r}->headers_in->{ $_[1] };
    }
    else {
        return $self->{r}->headers_in->{ $_[1] } = $_[2];
    }
}

# Do not want to return an APR::Table here
sub headers_in {
    my DW::Request::Apache2 $self = $_[0];
    return %{ $self->{r}->headers_in };
}

# searches for a given header and returns the value, or sets it
sub header_out {
    my DW::Request::Apache2 $self = $_[0];
    if ( scalar(@_) == 2 ) {
        return $self->{r}->headers_out->{ $_[1] };
    }
    else {
        return $self->{r}->headers_out->{ $_[1] } = $_[2];
    }
}

# Do not want to return an APR::Table here
sub headers_out {
    my DW::Request::Apache2 $self = $_[0];
    return %{ $self->{r}->headers_out };
}

# appends a value to a header
sub header_out_add {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->headers_out->add( $_[1], $_[2] );
}

# searches for a given header and returns the value, or sets it
sub err_header_out {
    my DW::Request::Apache2 $self = $_[0];
    if ( scalar(@_) == 2 ) {
        return $self->{r}->err_headers_out->{ $_[1] };
    }
    else {
        return $self->{r}->err_headers_out->{ $_[1] } = $_[2];
    }
}

# appends a value to a header
sub err_header_out_add {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->err_headers_out->add( $_[1], $_[2] );
}

# returns the ip address of the connected person
sub get_remote_ip {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->connection->client_ip;
}

# sets last modified
sub set_last_modified {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->set_last_modified( $_[1] );
}

sub status {
    my DW::Request::Apache2 $self = $_[0];
    if ( scalar(@_) == 2 ) {
        $self->{r}->status( $_[1] + 0 );
    }
    else {
        return $self->{r}->status();
    }
}

sub status_line {
    my DW::Request::Apache2 $self = $_[0];
    if ( scalar(@_) == 2 ) {

        # If we set status_line, we must also set status.
        my ($status) = $_[1] =~ m/^(\d+)/;
        $self->{r}->status($status);
        return $self->{r}->status_line( $_[1] );
    }
    else {
        return $self->{r}->status_line();
    }
}

# meets conditions
sub meets_conditions {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->meets_conditions;
}

sub print {
    my DW::Request::Apache2 $self = shift;
    return $self->{r}->print(@_);
}

sub read {
    my DW::Request::Apache2 $self = shift;
    my $ret = $self->{r}->read(@_);
    return $ret;
}

# return the internal Apache2 request object
sub r {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r};
}

# calls the method as a handler.
sub call_response_handler {
    my DW::Request::Apache2 $self = shift;

    $self->{r}->handler('perl-script');
    $self->{r}->push_handlers( PerlResponseHandler => $_[0] );

    return Apache2::Const::OK;
}

# FIXME: Temporary, until BML is gone / converted
# FIXME: This is only valid from a response handler
sub call_bml {
    my DW::Request::Apache2 $self = shift;

    $self->note( bml_filename => $_[0] );

    return Apache::BML::handler( $self->{r} );
}

# constants
sub OK {
    return Apache2::Const::OK;
}

sub HTTP_OK {
    return Apache2::Const::HTTP_OK;
}

sub HTTP_CREATED {
    return Apache2::Const::HTTP_CREATED;
}

sub MOVED_PERMANENTLY {
    return Apache2::Const::HTTP_MOVED_PERMANENTLY;
}

sub REDIRECT {
    return Apache2::Const::REDIRECT;
}

sub NOT_FOUND {
    return Apache2::Const::NOT_FOUND;
}

sub HTTP_GONE {
    return Apache2::Const::HTTP_GONE;
}

sub SERVER_ERROR {
    return Apache2::Const::SERVER_ERROR;
}

sub HTTP_UNAUTHORIZED {
    return Apache2::Const::HTTP_UNAUTHORIZED;
}

sub HTTP_BAD_REQUEST {
    return Apache2::Const::HTTP_BAD_REQUEST;
}

sub HTTP_UNSUPPORTED_MEDIA_TYPE {
    return Apache2::Const::HTTP_UNSUPPORTED_MEDIA_TYPE;
}

sub HTTP_SERVER_ERROR {
    return Apache2::Const::HTTP_INTERNAL_SERVER_ERROR;
}

sub HTTP_SERVICE_UNAVAILABLE {
    return Apache2::Const::HTTP_SERVICE_UNAVAILABLE;
}

sub HTTP_METHOD_NOT_ALLOWED {
    return Apache2::Const::HTTP_METHOD_NOT_ALLOWED;
}

sub FORBIDDEN {
    return Apache2::Const::FORBIDDEN;
}

# spawn a process for an external program
sub spawn {
    my DW::Request::Apache2 $self = shift;
    return $self->{r}->spawn_proc_prog(@_);
}

sub no_cache {
    my DW::Request::Apache2 $self = shift;
    return $self->{r}->no_cache(1);
}

1;
