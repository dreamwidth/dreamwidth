#!/usr/bin/perl
#
# DW::Controller::Dev
#
# This controller is for tiny pages related to dev work
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2010-2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

package DW::Controller::Dev;

use strict;
use warnings;
use DW::Routing;

DW::Routing->register_static( '/dev/classes', 'dev/classes.tt', app => 1 );


DW::Routing->register_regex( '/dev/tests/([^/]+)(?:/(.*))?', \&tests_handler, app => 1 )
    if $LJ::IS_DEV_SERVER;

sub tests_handler {
    my ( $opts ) = @_;
    my $test = $opts->subpatterns->[0];
    my $lib = $opts->subpatterns->[1] || "";

    my $r = DW::Request->get;

    # force a site scheme which only shows the bare content
    # but still prints out resources included using need_res
    $r->note( bml_use_scheme => "global" );

    # we don't validate the test name, so be careful!
    return DW::Template->render_template( "dev/tests.tt", {
            testname => $test,
            testlib  => $lib,
         } );
}
1;
