#!/usr/bin/perl
#
# DW::Request
#
# This module provides an abstraction layer for accessing data traditionally
# available through Apache::Request and similar modules.
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

=head1 NAME

DW::Request - This module provides an abstraction layer for accessing data traditionally available through Apache::Request and similar modules.

=head1 SYNOPSIS

=cut

package DW::Request;

use strict;
use DW::Request::Apache2;
use DW::Request::Standard;
use Hash::MultiValue;

our ( $cur_req, $determined );

=head1 Class Methods

=head2 C<< DW::Request->get >>

Returns a DW::Request object, based on what type of server environment are running under.

=cut

# creates a new DW::Request object, based on what type of server environment we
# are running under
sub get {

    # if we have already run this logic, return it.  makes it safe for us in case
    # the logic below is a little heavy so it doesn't run over and over.
    return $cur_req if $determined;

    # attempt Apache 2
    eval {
        eval "use Apache2::RequestUtil ();";
        my $r = Apache2::RequestUtil->request;
        $cur_req = DW::Request::Apache2->new($r)
            if $r;
    };

    # NOTE: the Standard module is not done through this path, it is done by
    # someone instantiating the module.  the module itself then sets $determined
    # and $cur_req appropriately.

    # hopefully one of the above worked and set $cur_req, but if not, then we
    # assume we're in fallback/command line mode
    $determined = 1;
    return $cur_req;
}

=head2 C<< DW::Request->reset >>

Resets the state. Called after we've finished up a request.

=cut

# called after we've finished up a request, or before a new request, as long as
# it's called sometime it doesn't matter exactly when it happens
sub reset {
    $determined = 0;
    $cur_req    = undef;
}

=head1 Required Object Methods

These methods work on any DW::Request subclass.

=head2 C<< $r->add_cookie( %args ) >>

Sends this cookie to the browser.  %args should be the same arguments passed to CGI::Cookie->new, except without the
initial hyphens CGI::Cookie asks you to use.  We don't use those.

=head2 C<< $r->call_bml( $filename ) >>

    return $r->call_bml( $filename );

Render a BML file.
Must be called as above, with the result being directly returned.

=head2 C<< $r->call_response_handler( $subref ) >>

    return $r->call_response_handler( \&handler );

This will ensure the sub gets called at some point soon, don't expect it to be called instantly, but also don't expect
this to be return immediately either.  Must be called as above, with the result being directly returned.

=head2 C<< $r->content >>

Return the raw content of the body.
This cannot be used with $r->post_args.

=head2 C<< $r->content_type( [$content_type] ) >>

Get or set the content type.

=head2 C<< $r->cookie( $name ) >>

Returns value(s) of cookie.

=head2 C<< $r->delete_cookie( %args ) >>

%args should be the same arguments passed to CGI::Cookie->new.

=head2 C<< $r->did_post >>

Returns true if the request used the POST method.  (see $r->method)

=head2 C<< $r->err_header_out( $header[, $value] ) >>

Sets or gets an response header that is also included on the error pages.

=head2 C<< $r->err_header_out_add( $header, $value ) >>

Adds another instance of a header for headers that allow multiple instances that is also included on the error pages.

=head2 C<< $r->get_args >>

Returns the GET arguments.

=head2 C<< $r->get_remote_ip >>

Returns the remote IP.

=head2 C<< $r->host >>

Return the (normalized) value of the Host header.

=head2 C<< $r->header_in( $header[, $value] ) >>

Sets or gets an request header.

=head2 C<< $r->headers_in >>

Returns all request headers.

=head2 C<< $r->header_out( $header[, $value] ) >>

Sets or gets an response header.

=head2 C<< $r->headers_out >>

Returns all response headers.

=head2 C<< $r->header_out_add( $header, $value ) >>

Adds another instance of a header for headers that allow multiple instances.

=head2 C<< $r->meets_conditions >>

This function inspects the client headers and determines if the response fulfills the specified requirements.

=head2 C<< $r->method >>

Returns the method.

=head2 C<< $r->note( $note[, $value] ) >>

Set or get a note.
This must be a plain string.

=head2 C<< $r->pnote( $note[, $value] ) >>

Set or get a Perl note.
This can be any perl ref or string.

=head2 C<< $r->post_args >>

Return the POST arguments.

=head2 C<< $r->print( $string ) >>

Append $string to the request.

=head2 C<< $r->query_string >>

Get the raw query string.

=head2 C<< $r->set_last_modified( $when ) >>

Set the last modified header to the specified time.

=head2 C<< $r->status( [$status] ) >>

Set or get the HTTP status code.

=head2 C<< $r->status_line( [$status] ) >>

Set or get the HTTP status code and message.

=head2 C<< $r->uri >>

Get the current requested uri.

=head1 Optional Object Methods

These may not be implemented on all DW::Request layers.

=head2 C<< $r->document_root >>

Returns the document root.

=head2 C<< $r->r >>

Get the internal request, if it exists.

=head2 C<< $r->read >>

Read raw data from the request.

=head2 C<< $r->response_content >>

Return the raw response content.

=head2 C<< $r->response_as_string >>

Return the response as a string.

=head2 C<< $r->spawn >>

Spawn off an external program.

=head2 C<< $r->redirect( $url ) >>

Redirect to a different URL.

=head2 C<< $r->no_cache >>

Turn off caching for this resource.

=head1 AUTHORS

=over

=item Mark Smith <mark@dreamwidth.org>

=item Andrea Nall <anall@andreanall.com>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2008-2013 by Dreamwidth Studios, LLC.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself. For a copy of the license, please reference
'perldoc perlartistic' or 'perldoc perlgpl'.

=cut

1;
