#!/usr/bin/perl
#
# DW::Request::Base
#
# Methods that are the same over most or all DW::Request modules
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2010 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Request::Base;

use strict;
use v5.10;
use Log::Log4perl;
my $log = Log::Log4perl->get_logger(__PACKAGE__);

use CGI::Cookie;
use CGI::Util qw( unescape );
use LJ::JSON;

use fields (
    'cookies_in',
    'cookies_in_multi',
    'cache',

    # If you use post_args, then you must not use content. If you use
    # content, you must not use post_args. Mutually exclusive.
    'content',      # raw content of the request (POST only!)
    'post_args',    # hashref of POST arguments (form encoding)
    'json_obj',     # JSON object that was posted (application/json)
    'uploads',      # arrayref of hashrefs of uploaded files

    # Query string arguments, every request might have these.
    'get_args',
    'msgs',
    'msgkey',
);

sub new {
    my $self = $_[0];
    $log->logconfess("This is a base class, you can't use it directly.")
        unless ref $self;

    $self->{cookies_in}       = undef;
    $self->{cookies_in_multi} = undef;
    $self->{post_args}        = undef;
    $self->{content}          = undef;
    $self->{get_args}         = undef;
    $self->{json_obj}         = undef;
    $self->{uploads}          = undef;
    $self->{msgs}             = undef;
    $self->{msgkey}           = undef;
}

sub host {
    return lc( $_[0]->header_in("Host") // "" );
}

sub cookie {
    my DW::Request::Base $self = $_[0];

    $self->parse( $self->header_in('Cookie') ) unless defined $self->{cookies_in};
    my $val = $self->{cookies_in}->{ $_[1] } || [];
    return wantarray ? @$val : $val->[0];
}

sub cookie_multi {
    my DW::Request::Base $self = $_[0];

    $self->parse( $self->header_in('Cookie') ) unless defined $self->{cookies_in_multi};
    return @{ $self->{cookies_in_multi}->{ $_[1] } || [] };
}

sub add_cookie {
    my DW::Request::Base $self = shift;
    my %args = (@_);

    $log->logconfess("Must provide name") unless $args{name};
    $log->logconfess("Must provide value (try delete_cookie if you really mean this)")
        unless exists $args{value};

    # we need to give all cookies the secure attribute on HTTPS sites
    if ( $LJ::PROTOCOL eq "https" ) {
        $args{secure} = 1;
    }
    else {    # if we're not secure, hopefully we're in a development environment
        $args{SameSite} = 'Lax' if $LJ::IS_DEV_SERVER;

        # TODO: test and see if the site works as expected with
        # SameSite=Lax turned on for all cookies - Lax prevents
        # cross-domain POST requests but GETs are allowed. Not
        # setting it at all is equivalent to SameSite=None, which
        # newer browsers only allow if the secure attribute is set.
    }

    # extraneous parenthesis inside map {} needed to force BLOCK mode map
    my $cookie = CGI::Cookie->new( map { ( "-$_" => $args{$_} ) } keys %args );
    $self->err_header_out_add( 'Set-Cookie' => $cookie );

    return $cookie;
}

sub delete_cookie {
    my DW::Request::Base $self = shift;
    my %args = (@_);

    $log->logconfess("Must provide name") unless $args{name};

    $args{value}   = '';
    $args{expires} = "-1d";

    return $self->add_cookie(%args);
}

# Per-request caching, these just live on the request object and are expected
# to be shared through the life of a request
sub cache {
    my DW::Request::Base $self = $_[0];
    if ( exists $_[2] ) {
        $log->debug("Request cache: set $_[1] to '$_[2]'");
        return $self->{cache}->{ $_[1] } = $_[2];
    }
    $log->debug("Request cache: get $_[1]");
    return $self->{cache}->{ $_[1] };
}

# Per RFC, method must be GET, POST, etc. We don't allow lowercase or any other
# presentation of the method to count as a post.
sub did_post {
    my DW::Request::Base $self = $_[0];
    return $self->method eq 'POST';
}

# Returns an array of uploads that were received in this request. Each upload
# is a hashref of certain data: body, name.
sub uploads {
    my DW::Request::Base $self = $_[0];
    return $self->{uploads} if defined $self->{uploads};

    my $body = $self->content;
    return $self->{uploads} = []
        unless $body && $self->method eq 'POST';

    my $sep =
        ( $self->header_in('Content-Type') =~ m!^multipart/form-data;\s*boundary=(\S+)! )
        ? $1
        : undef;
    $log->logcroak('Unknown content type in upload.') unless defined $sep;

    my @lines = split /\r\n/, $body;
    my $line  = shift @lines;
    $log->logcroak('Error parsing upload, it looks invalid.')
        unless $line eq "--$sep";

    my $ret = [];
    while (@lines) {
        $line = shift @lines;

        my %h;
        while ( defined $line && $line ne "" ) {
            $line =~ /^(\S+?):\s*(.+)/;
            $h{ lc($1) } = $2;
            $line = shift @lines;
        }
        while ( defined $line && $line ne "--$sep" ) {
            last if $line eq "--$sep--";
            $h{body} .= "\r\n" if $h{body};
            $h{body} .= $line;
            $line = shift @lines;
        }
        if ( $h{'content-disposition'} =~ /name="(\S+?)"/ ) {
            $h{name} = $1 || $2;
            push @$ret, \%h;
        }
    }

    return $self->{uploads} = $ret;
}

# returns a Hash::MultiValue object containing the post arguments if this is a
# valid request, or it returns undef.
sub post_args {
    my DW::Request::Base $self = $_[0];
    return $self->{post_args} if defined $self->{post_args};

    # Requires a POST with the proper content type for us to parse it, else just
    # bail and return empty.
    return Hash::MultiValue->new
        unless $self->method eq 'POST'
        && $self->header_in('Content-Type') =~ m!^application/x-www-form-urlencoded(?:;.+)?$!;

    return $self->{post_args} = $self->_string_to_multivalue( $self->content );
}

# returns a Hash::MultiValue of query string arguments
sub get_args {
    my DW::Request $self = shift;
    return $self->{get_args} if defined $self->{get_args};

    my %opts = @_;

    # We lowercase GET arguments because these are often typed by users, and
    # that's nicer on them.  This isn't always desired behavior, though.
    # In particular, it confuses post_fields_by_widget in LJ::Widget.

    my $lc = $opts{preserve_case} ? 0 : 1;

    return $self->{get_args} =
        $self->_string_to_multivalue( $self->query_string, lowercase => $lc );
}

# Returns a JSON object contained in the body of this request if and only if
# this request contains a JSON object.
sub json {
    my DW::Request $self = $_[0];
    return $self->{json_obj} if defined $self->{json_obj};

    # Content type must start with "application/json" and may have a semi-colon
    # followed by charset, etc. It must also be a POST.
    return undef
        unless $self->method eq 'POST'
        && $self->header_in('Content-Type') =~ m!^application/json(?:;.+)?$!;

    # If they submit bad JSON, we want to ignore the error and not crash. Just
    # let the caller know it wasn't a valid input.
    my $obj;
    eval { $obj = from_json( $self->content ); };
    return undef if $@;

    # Temporarily caches it, in case someone tries to ask for it again.
    return $self->{json_obj} = $obj;
}

# FIXME: This relies on the behavior parse_args
#   and the \0 seperated arguments. This should be cleaned
#   up at the same point parse_args is.
sub _string_to_multivalue {
    my ( $class, $input, %opts ) = @_;
    my %gets = LJ::parse_args($input);

    my @out;
    foreach my $key ( keys %gets ) {

        my @parts = defined $gets{$key} ? split( /\0/, $gets{$key} ) : '';
        push @out, map { $opts{lowercase} ? lc $key : $key => $_ } @parts;
    }

    return Hash::MultiValue->new(@out);
}

# simply sets the location header and returns REDIRECT
sub redirect {
    my %opts = @_;
    my DW::Request $self = $_[0];
    $self->header_out( Location => $_[1] );
    return $opts{permanent} ? $self->MOVED_PERMANENTLY : $self->REDIRECT;
}

# Constants for message alert levels
sub DEFAULT { return INFO(); }
sub INFO    { return 'info'; }
sub WARN    { return 'warning'; }
sub WARNING { return WARN(); };     # alias because both are common usages.
sub ERROR   { return 'error'; }
sub SUCCESS { return 'success'; }
my @MSG_LEVELS = ( DEFAULT(), INFO(), WARN(), ERROR(), SUCCESS() );

# Generate memcache key for session messages
sub msgkey {
    my DW::Request $self = $_[0];
    return $self->{msgkey} if defined $self->{msgkey};

    my $cookie = $self->cookie('ljuniq');
    if ($cookie) {
        my ( $uniq, $ts ) = split( /:/, $self->cookie('ljuniq') );
        $self->{msgkey} = "req_msgs:$uniq";
    }
    return $self->{msgkey};
}

# Gets session messages to display inline on pages
sub msgs {
    my DW::Request $self = $_[0];

    return $self->{msgs} if defined $self->{msgs};
    my $msgkey = $self->msgkey;
    $self->{msgs} = LJ::MemCache::get($msgkey) if $msgkey;
    return $self->{msgs};
}

# Clear session messages from the request and from memcache.
# Should be used after messages have been displayed to user.
sub clear_msgs {
    my DW::Request $self = $_[0];

    my $msgkey = $self->msgkey;
    LJ::MemCache::delete($msgkey) if $msgkey;
    $self->{msgs} = undef;

    return 1;
}

# Add a session message to be displayed inline. Log level can be
# one of INFO, WARNING, ERROR, SUCCESS, or DEFAULT, or none.
sub add_msg {
    my DW::Request $self = $_[0];
    my $msg              = $_[1];
    my $level            = $_[2];

    $log->logcroak("Invalid message level $level")
        if $level && !( grep { $level eq $_ } @MSG_LEVELS );
    $msg =
        $level ? { 'item' => $msg, 'level' => $level } : { 'item' => $msg, 'level' => DEFAULT() };

    my $msgs = $self->msgs;
    if ($msgs) {
        push @$msgs, $msg;
    }
    else {
        $msgs = [$msg];
    }

    my $msgkey = $self->msgkey;
    LJ::MemCache::set( $msgkey, $msgs ) if $msgkey;
    $self->{msgs} = $msgs;
    return 1;
}

# Add a session message and redirect. This is a helper
# method that wraps add_msg and redirect in one call.
sub msg_redirect {
    my DW::Request $self = $_[0];
    my $msg              = $_[1];
    my $level            = $_[2];
    my $location         = $_[3];

    $self->add_msg( $msg, $level );
    return $self->redirect($location);
}

# indicates that this request has been handled
sub OK { return 0; }

# HTTP status codes that we return in other methods
sub HTTP_OK                     { return 200; }
sub HTTP_CREATED                { return 201; }
sub MOVED_PERMANENTLY           { return 301; }
sub REDIRECT                    { return 302; }
sub NOT_FOUND                   { return 404; }
sub HTTP_GONE                   { return 410; }
sub SERVER_ERROR                { return 500; }
sub HTTP_UNAUTHORIZED           { return 401; }
sub HTTP_BAD_REQUEST            { return 400; }
sub HTTP_UNSUPPORTED_MEDIA_TYPE { return 415; }
sub HTTP_SERVER_ERROR           { return 500; }
sub HTTP_METHOD_NOT_ALLOWED     { return 405; }
sub FORBIDDEN                   { return 403; }

# Unimplemented method block. These are things that the derivative classes must
# implement. In the future, it'd be nice to roll as many of these up to the base
# as we can, but that's in the post-Apache days.
sub header_out {
    $log->logconfess('Unimplemented call on base class.');
}
*header_out_add     = \&header_out;
*err_header_out     = \&header_out;
*err_header_out_add = \&header_out;
*header_in          = \&header_out;
*header_in_add      = \&header_out;
*err_header_in      = \&header_out;
*err_header_in_add  = \&header_out;
*method             = \&header_out;

sub call_response_handler {

    # Default behavior is to call immediately
    return $_[1]->();
}

#
# Following sub was copied from CGI::Cookie and modified.
#
# Copyright 1995-1999, Lincoln D. Stein.  All rights reserved.
# It may be used and modified freely, but I do request that this copyright
# notice remain attached to the file.  You may modify this module as you
# wish, but if you redistribute a modified version, please attach a note
# listing the modifications you have made.
#
sub parse {
    my DW::Request::Base $self = $_[0];
    my %results;
    my %results_multi;

    my @pairs = split( "[;,] ?", defined $_[1] ? $_[1] : '' );
    foreach (@pairs) {
        $_ =~ s/\s*(.*?)\s*/$1/;
        my ( $key, $value ) = split( "=", $_, 2 );

        # Some foreign cookies are not in name=value format, so ignore
        # them.
        next unless defined($value);
        my @values = ();
        if ( $value ne '' ) {
            @values = map unescape($_), split( /[&;]/, $value . '&dmy' );
            pop @values;
        }
        $key = unescape($key);
        $results{$key} ||= \@values;
        push @{ $results_multi{$key} }, \@values;
    }

    $self->{cookies_in}       = \%results;
    $self->{cookies_in_multi} = \%results_multi;
}

1;
