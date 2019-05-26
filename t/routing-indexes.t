# t/routing-indexes.t
#
# Routing tests: /index pages
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

BEGIN { require "$ENV{LJHOME}/cgi-bin/LJ/Directories.pm"; }
use DW::Routing::Test tests => 6;

$DW::Routing::T_TESTING_ERRORS = 1;

expected_format('html');

begin_tests();

DW::Routing->register_string( "/xx3/index", \&handler, app => 1, args => "it_worked_redir" );

handle_request( "/xx3/",      "/xx3/",      1, "it_worked_redir" );
handle_request( "/xx3/index", "/xx3/index", 1, "it_worked_redir" );
handle_redirect( '/xx3', '/xx3/' );

handle_redirect( '/xx3?kittens=cute', '/xx3/?kittens=cute' );

# 4

DW::Routing->register_string( "/index", \&handler, app => 1, args => "it_worked_redir" );

handle_request( "/",      "/",      1, "it_worked_redir" );
handle_request( "/index", "/index", 1, "it_worked_redir" );

# 6
