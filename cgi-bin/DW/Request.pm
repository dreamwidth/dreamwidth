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
use DW::Request::Apache2;

use vars qw( $cur_req $determined );

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
        $cur_req = DW::Request::Apache2->new( $r )
            if $r;
    };

    # hopefully one of the above worked and set $cur_req, but if not, then we
    # assume we're in fallback/command line mode
    $determined = 1;
    return $cur_req;
}

# called after we've finished up a request, or before a new request, as long as
# it's called sometime it doesn't matter exactly when it happens
sub reset {
    $determined = 0;
    $cur_req = undef;
}

1;
