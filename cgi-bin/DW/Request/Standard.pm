#!/usr/bin/perl
#
# DW::Request::Standard
#
# Abstraction layer for standard HTTP::Request/HTTP::Response based systems.
# We don't care who's giving us the data, ...
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Request::Standard;
use strict;
use DW::Request::Base;
use base 'DW::Request::Base';

use Carp qw/ confess cluck /;
use HTTP::Request;
use HTTP::Response;
use HTTP::Status qw//;

use fields (
    'req',    # The HTTP::Request object
    'res',    # a HTTP::Response object
    'notes',
    'pnotes',

    # we have to parse these out ourselves
    'uri',
    'querystring',

    'read_offset'
);

# creates a new DW::Request object, based on what type of server environment we
# are running under
sub new {
    my DW::Request::Standard $self = $_[0];
    $self = fields::new($self) unless ref $self;
    $self->SUPER::new;

    # setup object
    $self->{req}         = $_[1];
    $self->{res}         = HTTP::Response->new(200);
    $self->{uri}         = $self->{req}->uri;
    $self->{notes}       = {};
    $self->{pnotes}      = {};
    $self->{read_offset} = 0;

    # now stick ourselves as the primary request ...
    unless ($DW::Request::cur_req) {
        $DW::Request::determined = 1;
        $DW::Request::cur_req    = $self;
    }

    # done
    return $self;
}

# current document root
sub document_root {
    confess "Not implemented, doesn't matter here ...\n";
}

# method string GET, POST, etc
sub method {
    my DW::Request::Standard $self = $_[0];
    return $self->{req}->method;
}

# the URI requested (does not include host:port info)
sub uri {
    my DW::Request::Standard $self = $_[0];
    return $self->{uri}->path;
}

# This sets the content-type on the response. This is NOT a request method. For
# that, use the header_in method and check Content-Type.
sub content_type {
    my DW::Request::Standard $self = $_[0];
    return $self->{res}->content_type( $_[1] );
}

# returns the query string
sub query_string {
    my DW::Request::Standard $self = $_[0];
    return $self->{uri}->query;
}

# returns the raw content of the body; note that this can be particularly
# slow, so you should only call this if you really need it...
sub content {
    my DW::Request::Standard $self = $_[0];

    # keep a local copy ... bloats memory, and useless, why?
    return $self->{content} if defined $self->{content};
    return $self->{content} = $self->{req}->content;
}

# content of our response object
sub response_content {
    my DW::Request::Standard $self = $_[0];
    return $self->{res}->content;
}

# return a response as a string
sub response_as_string {
    my DW::Request::Standard $self = $_[0];
    return $self->{res}->as_string;
}

# searches for a given note and returns the value, or sets it
sub note {
    my DW::Request::Standard $self = $_[0];
    if ( scalar(@_) == 2 ) {
        return $self->{notes}->{ $_[1] };
    }
    else {
        return $self->{notes}->{ $_[1] } = $_[2];
    }
}

# searches for a given pnote and returns the value, or sets it
sub pnote {
    my DW::Request::Standard $self = $_[0];
    if ( scalar(@_) == 2 ) {
        return $self->{pnotes}->{ $_[1] };
    }
    else {
        return $self->{pnotes}->{ $_[1] } = $_[2];
    }
}

# searches for a given header and returns the value, or sets it
sub header_in {
    my DW::Request::Standard $self = $_[0];
    if ( scalar(@_) == 2 ) {
        return $self->{req}->header( $_[1] );
    }
    else {
        return $self->{req}->header( $_[1] => $_[2] );
    }
}

sub headers_in {
    my DW::Request::Standard $self = $_[0];
    return $self->{req}->headers;
}

# searches for a given header and returns the value, or sets it
sub header_out {
    my DW::Request::Standard $self = $_[0];
    if ( scalar(@_) == 2 ) {
        return $self->{res}->header( $_[1] );
    }
    else {
        return $self->{res}->header( $_[1] => $_[2] );
    }
}

sub headers_out {
    my DW::Request::Standard $self = $_[0];
    return $self->{res}->headers;
}

# appends a value to a header
sub header_out_add {
    my DW::Request::Standard $self = $_[0];
    return $self->{res}->push_header( $_[1], $_[2] );
}

# this may not be precisely correct?  maybe we need to maintain our
# own set of headers that are separate for errors... FIXME: investigate
*err_header_out     = \&header_out;
*err_header_out_add = \&header_out_add;

# returns the ip address of the connected person
sub get_remote_ip {
    my DW::Request::Standard $self = $_[0];

    # FIXME: this needs to support more than just the header ... what if we're not
    # running behind a proxy?  can we use the environment?  do we fake it?  for now,
    # assume that if there is no X-Forwarded-For or we don't trust it, we just put in
    # a bogus IP...
    return '127.0.0.100' unless $LJ::TRUST_X_HEADERS;

    my @ips = split /\s*,\s*/, $self->{req}->header('X-Forwarded-For');
    return '127.0.0.101' unless @ips && $ips[0];

    return $ips[0];
}

# sets last modified, this is called so that we set it up on the response object
sub set_last_modified {
    my DW::Request::Standard $self = $_[0];
    return $self->{res}->header( 'Last-Modified' => LJ::time_to_http( $_[1] ) );
}

# this is a response method
sub status {
    my DW::Request::Standard $self = $_[0];
    if ( scalar(@_) == 2 ) {

        # Set message to a default string, just setting code won't do it.
        my $code = $_[1] || 500;
        $self->{res}->code($code);
        $self->{res}->message( HTTP::Status::status_message($code) );
    }
    return $self->{res}->code;
}

# build or return a status line (RESPONSE)
sub status_line {
    my DW::Request::Standard $self = $_[0];
    if ( scalar(@_) == 2 ) {

        # We must set code and message seperately.
        if ( $_[1] =~ m/^(\d+)\s+(.+)$/ ) {
            $self->{res}->code($1);
            $self->{res}->message($2);
        }
    }
    return $self->{res}->status_line;
}

# meets conditions
# conditional GET triggered on:
#   If-Modified-Since
#   If-Unmodified-Since     FIXME: implement
#   If-Match                FIXME: implement
#   If-None-Match           FIXME: implement
#   If-Range                FIXME: implement
sub meets_conditions {
    my DW::Request::Standard $self = $_[0];

    return $self->OK
        if LJ::http_to_time( $self->header_in("If-Modified-Since") ) <=
        LJ::http_to_time( $self->header_out("Last-Modified") );

    # FIXME: this should be pretty easy ... check the If headers (only time ones?)
    # and see if they're good or not.  return proper status code here (OK, NOT_MODIFIED)
    # go see the one caller in LJ::Feed
    return 0;
}

sub print {
    my DW::Request::Standard $self = $_[0];
    $self->{res}->add_content( $_[1] );
    return;
}

# FIXME(dre): this may not be the most efficient way but is
# totally fine when we are just using this for tests.
# We *may* need to revisit this if we use this for serving pages
# IMPORTANT: Do not pull out $_[1] to a variable in this sub
sub read {
    my DW::Request::Standard $self = $_[0];
    die "missing required arguments" if scalar(@_) < 3;

    my $prefix = '';
    if ( exists $_[3] ) {
        die "Negative offsets not allowed" if $_[3] < 0;
        $prefix = substr( $_[1], 0, $_[3] );
    }

    die "Length cannot be negative" if $_[2] < 0;
    my $ov = substr( $self->content, $self->{read_offset}, $_[2] );

    # Given $_[1] and whatever was passed in as the first argument are the
    # same exact scalar this will set *that* variable too.
    $_[1] = $prefix . $ov;

    $self->{read_offset} += length($ov);
    return length($ov);
}

# return the internal Standard request object... in this case, we are
# just going to return ourself, as anybody that needs the request object
# is probably an old Apache style caller that needs updating
sub r {
    my DW::Request::Standard $self = $_[0];
    cluck "DW::Request::Standard->r called, please update the caller.";
    return $self;
}

# calls the method as a handler.
sub call_response_handler {
    return $_[1]->();
}

sub call_bml {
    confess "call_bml not (yet) supported";
}

# spawn a process for an external program
sub spawn {
    confess "Sorry, spawning not implemented.";
}

sub no_cache {
    confess "Sorry, no_cache not implemented.";
}
1;
