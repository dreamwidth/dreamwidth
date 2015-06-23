# t/routing-errors.t
#
# Routing tests: Error pages
#
# Authors:
#      Andrea Nall <anall@andreanall.com>
#
# Copyright (c) 2011 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#
use strict;
use warnings;

BEGIN { require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm"; };
use DW::Routing::Test tests => 4;

$DW::Routing::T_TESTING_ERRORS = 1;

expected_format('html');

begin_tests();

DW::Routing->register_string( "/test/die/all_format", \&died_handler, app => 1, formats => 1 );

handle_server_error( "/test die implied_format (app)", "/test/die/all_format", "html" );
handle_server_error( "/test die .json format (app)", "/test/die/all_format.json", "json" );
handle_server_error( "/test die .html format (app)", "/test/die/all_format.html", "html" );
handle_server_error( "/test die .blah format (app)", "/test/die/all_format.blah", "blah" );
# 4

sub died_handler {
    die "deliberate die()";
}
