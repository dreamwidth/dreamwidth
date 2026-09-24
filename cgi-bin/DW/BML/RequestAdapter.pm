#!/usr/bin/perl
#
# DW::BML::RequestAdapter
#
# Minimal adapter that makes DW::Request look enough like an Apache2 request
# object for BML's public API functions (BML::get_request(), etc.) to work,
# and for held external hooks that still expect that shape. Split out of
# DW::BML so callers that only need the adapter don't have to load the whole
# BML rendering engine.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::BML::RequestAdapter;

use strict;

sub new {
    my ( $class, $dw_request ) = @_;
    return bless { r => $dw_request }, $class;
}

sub uri {
    return $_[0]->{r}->uri;
}

sub method {
    return $_[0]->{r}->method;
}

sub args {
    return $_[0]->{r}->query_string;
}

sub path_info {
    return '';    # BML pages don't use path_info in Plack context
}

sub hostname {
    return $_[0]->{r}->host;
}

sub header_only {
    return $_[0]->{r}->method eq 'HEAD' ? 1 : 0;
}

sub status {
    my ( $self, $val ) = @_;
    if ( defined $val ) {
        return $self->{r}->status($val);
    }
    return $self->{r}->status;
}

sub content_type {
    my ( $self, $val ) = @_;
    if ( defined $val ) {
        return $self->{r}->content_type($val);
    }
    return $self->{r}->content_type;
}

sub print {
    my ( $self, @args ) = @_;
    $self->{r}->print($_) for @args;
}

sub no_cache {
    return $_[0]->{r}->no_cache;
}

# headers_in: returns a tied hash-like object for reading request headers
sub headers_in {
    return DW::BML::RequestAdapter::HeadersIn->new( $_[0]->{r} );
}

# headers_out / err_headers_out: returns an object for setting response headers
sub headers_out {
    return DW::BML::RequestAdapter::HeadersOut->new( $_[0]->{r} );
}

sub err_headers_out {
    return DW::BML::RequestAdapter::ErrHeadersOut->new( $_[0]->{r} );
}

# notes: returns a tied hash-like object backed by DW::Request->note()
sub notes {
    return DW::BML::RequestAdapter::Notes->new( $_[0]->{r} );
}

# connection: returns an object with client_ip, remote_host, user
sub connection {
    return DW::BML::RequestAdapter::Connection->new( $_[0]->{r} );
}

# document_root: return $LJ::HTDOCS
sub document_root {
    return $LJ::HTDOCS;
}

# pool: stub for cleanup_register (no-op under Plack)
sub pool {
    return DW::BML::RequestAdapter::Pool->new;
}

# dir_config: stub, returns undef (no Apache dir config under Plack)
sub dir_config {
    return undef;
}

# Apache constant stubs for code that calls $r->OK, $r->NOT_FOUND, etc.
sub OK        { return 0; }
sub NOT_FOUND { return 404; }
sub DECLINED  { return -1; }

sub status_line {
    my ( $self, $val ) = @_;
    if ( defined $val ) {
        $self->{_status_line} = $val;
        return;
    }
    return $self->{_status_line};
}

# finfo: no-op
sub finfo { }

# filename
sub filename {
    return $_[0]->{_filename};
}

###########################################################################
# HeadersIn: read-only hash-like access to request headers
###########################################################################

package DW::BML::RequestAdapter::HeadersIn;

sub new {
    my ( $class, $r ) = @_;
    tie my %h, 'DW::BML::RequestAdapter::HeadersIn::Tie', $r;
    return bless [ $r, \%h ], $class;
}

use overload '%{}' => sub { return $_[0]->[1]; }, fallback => 1;

package DW::BML::RequestAdapter::HeadersIn::Tie;

sub TIEHASH { return bless { r => $_[1] }, $_[0] }
sub FETCH  { return $_[0]->{r}->header_in( $_[1] ) }
sub EXISTS { return defined $_[0]->{r}->header_in( $_[1] ) }
sub STORE  { }                                                 # read-only

###########################################################################
# HeadersOut: hash-like access to response headers
###########################################################################

package DW::BML::RequestAdapter::HeadersOut;

sub new {
    my ( $class, $r ) = @_;
    tie my %h, 'DW::BML::RequestAdapter::HeadersOut::Tie', $r;
    return bless [ $r, \%h ], $class;
}

use overload '%{}' => sub { return $_[0]->[1]; }, fallback => 1;

package DW::BML::RequestAdapter::HeadersOut::Tie;

sub TIEHASH { return bless { r => $_[1] }, $_[0] }
sub FETCH { return $_[0]->{r}->header_out( $_[1] ) }
sub STORE { $_[0]->{r}->header_out( $_[1], $_[2] ) }

###########################################################################
# ErrHeadersOut: for Set-Cookie via ->add()
###########################################################################

package DW::BML::RequestAdapter::ErrHeadersOut;

sub new {
    my ( $class, $r ) = @_;
    return bless { r => $r }, $class;
}

sub add {
    my ( $self, $name, $value ) = @_;
    $self->{r}->err_header_out_add( $name, $value );
}

###########################################################################
# Notes: hash-like access to per-request notes
###########################################################################

package DW::BML::RequestAdapter::Notes;

sub new {
    my ( $class, $r ) = @_;
    tie my %h, 'DW::BML::RequestAdapter::Notes::Tie', $r;

    # Use array-based object to avoid hash dereference triggering overload
    return bless [ $r, \%h ], $class;
}

sub set {
    my ( $self, $key, $value ) = @_;
    $self->[0]->note( $key, $value );
}

use overload '%{}' => sub { return $_[0]->[1]; }, fallback => 1;

package DW::BML::RequestAdapter::Notes::Tie;

sub TIEHASH { return bless { r => $_[1] }, $_[0] }
sub FETCH { return $_[0]->{r}->note( $_[1] ) }
sub STORE { $_[0]->{r}->note( $_[1], $_[2] ) }

###########################################################################
# Connection: client_ip, remote_host, user
###########################################################################

package DW::BML::RequestAdapter::Connection;

sub new {
    my ( $class, $r ) = @_;
    return bless { r => $r }, $class;
}

sub client_ip {
    return $_[0]->{r}->get_remote_ip;
}

sub remote_host {
    return $_[0]->{r}->get_remote_ip;
}

sub user {
    return undef;
}

###########################################################################
# Pool: stub for cleanup_register
###########################################################################

package DW::BML::RequestAdapter::Pool;

sub new {
    return bless {}, $_[0];
}

sub cleanup_register {

    # No-op under Plack -- cleanup happens at end of request naturally
}

1;
