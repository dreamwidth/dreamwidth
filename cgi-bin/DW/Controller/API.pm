#!/usr/bin/perl
#
# DW::Controller::API
#
# API base implementation and helper functions.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::API;

use strict;
use warnings;
use DW::Routing;
use DW::Request;
use DW::Controller;
use LJ::JSON;

use Carp qw/ croak /;

use base qw/ Exporter /;
@DW::Controller::API::EXPORT = qw/ api_ok api_error /;

# Usage: return api_error( $r->STATUS_CODE_CONSTANT,
#                          'format/message', [arg, arg, arg...] )
# Returns a standard format JSON error message.
# The first argument is the status code
# The second argument is a string that might be a format string:
# it's passed to sprintf with the rest of the
# arguments.
sub api_error {
    my $status_code = shift;
    my $message     = scalar @_ >= 1 ? sprintf( shift, @_ ) : 'Unknown error.';

    my $res = {
        success => 0,
        error   => $message,
    };

    my $r = DW::Request->get;
    $r->print( to_json($res) );
    $r->status($status_code);
    return;
}

# Usage: return api_ok( SCALAR )
# Takes a scalar as input, then constructs an output JSON object. The output
# object is always of the format:
#   { success => 0/1, result => SCALAR }
# SCALAR can of course be a hashref, arrayref, or value.
sub api_ok {
    croak 'api_ok takes one argument only'
        unless scalar @_ == 1;

    my $res = {
        success => 1,
        result  => $_[0],
    };

    my $r = DW::Request->get;
    $r->print( to_json($res) );
    $r->status(200);
    return;
}

1;
