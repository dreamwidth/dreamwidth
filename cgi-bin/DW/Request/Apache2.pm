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
use Apache2::Response ();
use Apache2::RequestRec ();
use Apache2::RequestUtil ();
use Apache2::RequestIO ();
use Apache2::SubProcess ();
use Hash::MultiValue;
use Carp qw/ croak confess /;

use fields (
            'r',         # The Apache2::Request object

            # these are mutually exclusive; if you use one you can't use the other
            'content',   # raw content
            'post_args', # hashref of POST arguments
            'uploads',   # arrayref of hashrefs of uploaded files
        );

# creates a new DW::Request object, based on what type of server environment we
# are running under
sub new {
    my DW::Request::Apache2 $self = $_[0];
    $self = fields::new( $self ) unless ref $self;
    $self->SUPER::new;

    # setup object
    $self->{r}         = $_[1];
    $self->{post_args} = undef;
    $self->{content}   = undef;

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

sub content_type {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->content_type($_[1]);
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

    die "already loaded post_args\n"
        if defined $self->{post_args};

    return $self->{content} if defined $self->{content};

    my $buff = '';
    while ( my $ct = $self->{r}->read( my $buf, 65536 ) ) {
        $buff .= $buf;
        last if $ct < 65536;
    }
    return $self->{content} = $buff;
}

sub post_args {
    my DW::Request::Apache2 $self = $_[0];

    die "already loaded content\n"
        if defined $self->{content};

    return $self->{post_args} if defined $self->{post_args};

    my $tmp_r = Apache2::Request->new( $self->{r} );
    my $data = $tmp_r->body;

    my @out;
    my %seen_keys;
    foreach my $key ( keys %$data ) {
        next if $seen_keys{$key}++;
        my @val = $data->get( $key );
        next unless @val;
        push @out, map { $key => $_ } @val;
    }

    return $self->{post_args} = Hash::MultiValue->new( @out );
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

# searches for a given pnote and returns the value, or sets it
sub pnote {
    my DW::Request::Apache2 $self = $_[0];
    if ( scalar( @_ ) == 2 ) {
        return $self->{r}->pnotes->{$_[1]};
    } else {
        return $self->{r}->pnotes->{$_[1]} = $_[2];
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

# searches for a given header and returns the value, or sets it
sub header_out {
    my DW::Request::Apache2 $self = $_[0];
    if ( scalar( @_ ) == 2 ) {
        return $self->{r}->headers_out->{$_[1]};
    } else {
        return $self->{r}->headers_out->{$_[1]} = $_[2];
    }
}

# appends a value to a header
sub header_out_add {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->headers_out->add( $_[1] , $_[2] );
}

# searches for a given header and returns the value, or sets it
sub err_header_out {
    my DW::Request::Apache2 $self = $_[0];
    if ( scalar( @_ ) == 2 ) {
        return $self->{r}->err_headers_out->{$_[1]};
    } else {
        return $self->{r}->err_headers_out->{$_[1]} = $_[2];
    }
}

# appends a value to a header
sub err_header_out_add {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->err_headers_out->add( $_[1] , $_[2] );
}

# returns the ip address of the connected person
sub get_remote_ip {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->connection->remote_ip;
}

# sets last modified
sub set_last_modified {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{r}->set_last_modified($_[1]);
}

sub status {
    my DW::Request::Apache2 $self = $_[0];
    if (scalar(@_) == 2) {
        $self->{r}->status($_[1]+0);
    } else {
        return $self->{r}->status();
    }
}

sub status_line {
    my DW::Request::Apache2 $self = $_[0];
    if (scalar(@_) == 2) {
        # If we set status_line, we must also set status.
        my ($status) = $_[1] =~ m/^(\d+)/;
        $self->{r}->status($status);
        return $self->{r}->status_line($_[1]);
    } else {
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

    $self->{r}->handler( 'perl-script' );
    $self->{r}->push_handlers( PerlResponseHandler => $_[0] );

    return Apache2::Const::OK;
}

# FIXME: Temporary, until BML is gone / converted
# FIXME: This is only valid from a response handler
sub call_bml {
    my DW::Request::Apache2 $self = shift;

    $self->note(bml_filename => $_[0]);

    return Apache::BML::handler($self->{r});
}

# simply sets the location header and returns REDIRECT
sub redirect {
    my DW::Request::Apache2 $self = $_[0];
    $self->header_out( Location => $_[1] );
    return $self->REDIRECT;
}

# Returns an array of uploads that were received in this request. Each upload
# is a hashref of certain data.
sub uploads {
    my DW::Request::Apache2 $self = $_[0];
    return $self->{uploads} if defined $self->{uploads};

    my $body = $self->content;
    return $self->{uploads} = []
        unless $body && $self->method eq 'POST';

    my $sep = ( $self->header_in( 'Content-Type' ) =~ m!^multipart/form-data;\s*boundary=(\S+)! ) ? $1 : undef;
    croak 'Unknown content type in upload.' unless defined $sep;

    my @lines = split /\r\n/, $body;
    my $line = shift @lines;
    croak 'Error parsing upload, it looks invalid.'
        unless $line eq "--$sep";

    my $ret = [];
    while ( @lines ) {
        $line = shift @lines;

        my %h;
        while (defined $line && $line ne "") {
            $line =~ /^(\S+?):\s*(.+)/;
            $h{lc($1)} = $2;
            $line = shift @lines;
        }
        while (defined $line && $line ne "--$sep") {
            last if $line eq "--$sep--";
            $h{body} .= "\r\n" if $h{body};
            $h{body} .= $line;
            $line = shift @lines;
        }
        if ($h{'content-disposition'} =~ /name="(\S+?)"/) {
            $h{name} = $1 || $2;
            push @$ret, \%h;
        }
    }

    return $self->{uploads} = $ret;
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

sub REDIRECT {
    return Apache2::Const::REDIRECT;
}

sub NOT_FOUND {
    return Apache2::Const::NOT_FOUND;
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

sub HTTP_METHOD_NOT_ALLOWED {
    return Apache2::Const::HTTP_METHOD_NOT_ALLOWED;
}

sub FORBIDDEN {
    return Apache2::Const::FORBIDDEN;
}

# spawn a process for an external program
sub spawn {
    my DW::Request::Apache2 $self = shift;
    return $self->{r}->spawn_proc_prog( @_ );
}

1;
