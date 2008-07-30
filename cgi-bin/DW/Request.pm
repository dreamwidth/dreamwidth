#!/usr/bin/perl
#
# DW::Request
#
# This module provides an abstraction layer for accessing data traditionally
# available through Apache::Request and similar modules.
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

package DW::Request;

use strict;
use Apache2::RequestUtil ();
use DW::Request::Apache2;

use vars qw( $cur_req );

# creates a new DW::Request object, based on what type of server environment we
# are running under
sub get {
    # if we have a request, return it
    return $cur_req if $cur_req;

    # attempt Apache 2 
    eval {
        require 'Apache2::RequestUtil';
        my $r = Apache2::RequestUtil->request;
        return $cur_req = DW::Request::Apache2->new( $r )
            if $r;
    };

    # okay, we fell through, something is really busted
    die "DW::Request failed to identify current operating environment.";
}

# called after we've finished up a request, or before a new request, as long as
# it's called sometime it doesn't matter exactly when it happens
sub reset {
    $cur_req = undef;
}

1;
