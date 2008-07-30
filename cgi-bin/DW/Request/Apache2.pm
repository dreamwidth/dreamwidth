#!/usr/bin/perl
#
# DW::Request::Apache2
#
# Abstraction layer for Apache 2/mod_perl 2.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2008 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Request::Apache2;

use strict;
use Apache2::Const qw/ :common REDIRECT HTTP_NOT_MODIFIED /;
use Apache2::Log ();
use Apache2::Request;
use Apache2::RequestRec ();
use Apache2::RequestUtil ();
use Apache2::RequestIO ();

use fields (
            'r',         # The Apache2::Request object
            'post_args', # hashref of POST arguments
        );

# creates a new DW::Request object, based on what type of server environment we
# are running under
sub new {
    my DW::Request::Apache2 $self = $_[0];
    $self = fields::new( $self ) unless ref $self;

    # setup object
    $self->{r}         = $_[1];
    $self->{post_args} = undef;

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

# returns the query string
sub query_string {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->args;
}

# get POST arguments as an APR::Table object (which is a tied hashref)
sub post_args {
    my DW::Request::Apache2 $self = $_[0];
    unless ( $self->{post_args} ) {
        my $tmp_r = Apache2::Request->new( $self->{r} );
        $self->{post_args} = $tmp_r->body;
    }
    return $self->{post_args};
}

# searches for a given note and returns the value, or sets it
sub note {
    my DW::Request::Apache2 $self = $_[0];
    if ( scalar( @_ ) == 2 ) {
        return $self->{r}->notes->{$_[1]};
    } else {
        return $self->{r}->notes->{$_[1]} = $_[2];
    }
}

# searches for a given header and returns the value, or sets it
sub header_in {
    my DW::Request::Apache2 $self = $_[0];
    if ( scalar( @_ ) == 2 ) {
        return $self->{r}->headers_in->{$_[1]};
    } else {
        return $self->{r}->headers_in->{$_[1]} = $_[2];
    }
}

# returns the ip address of the connected person
sub get_remote_ip {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->connection->remote_ip;
}

1;
