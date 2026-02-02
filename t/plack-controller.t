#!/usr/bin/perl
# t/plack-controller.t
#
# Tests that DW::Controller::Login renders through the full Plack stack.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use v5.10;

use Test::More;
use HTTP::Request::Common;
use Plack::Test;

BEGIN {
    $LJ::_T_CONFIG = 1;
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

# Load the Plack app
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Test: GET /login returns 200 with login form HTML
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "http://localhost/login?skin=global" );

    is( $res->code, 200, "GET /login returns 200" );
    like( $res->content, qr/<form/i, "Response contains a login form" );
};

done_testing;
