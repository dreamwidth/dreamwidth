# t/routing-formats.t
#
# Routing tests: Formats
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
use DW::Routing::Test tests => 12;

expected_format('html');

begin_tests();

DW::Routing->register_string( "/test/all", \&handler, app => 1, user => 1, ssl => 1, format => 'json', args => "it_worked_multi", formats => [ 'json', 'format' ] );

expected_format('json');
handle_request( "/test all json (app)" , "/test/all", 1, "it_worked_multi");
handle_request( "/test all json (ssl)" , "/test/all", 1, "it_worked_multi", ssl => 1 );
handle_request( "/test all json (user)", "/test/all", 1, "it_worked_multi", username => 'test' );

expected_format('format');
handle_request( "/test all format (app)" , "/test/all.format", 1, "it_worked_multi");
handle_request( "/test all format (ssl)" , "/test/all.format", 1, "it_worked_multi", ssl => 1 );
handle_request( "/test all format (user)", "/test/all.format", 1, "it_worked_multi", username => 'test' );
# 6

DW::Routing->register_string( "/test/app", \&handler, app => 1, args => "it_worked_app", formats => [ 'html', 'format' ] );
DW::Routing->register_regex( qr !^/r/app(/.+)$!, \&regex_handler, app => 1, args => ["/test", "it_worked_app"], formats => [ 'html', 'format' ] );

expected_format('json');
handle_request( "/test app (app) invalid" , "/test/app.json", 1, undef, expected_error => 404 );
handle_request( "/r/app (app) invalid" , "/r/app/test.json", 1, undef, expected_error => 404 );
# 8

DW::Routing->register_string( "/test/app/implied_format", \&handler, app => 1, args => "it_worked_app_if" );

expected_format('html');
handle_request( "/test app implied_format (app)" , "/test/app/implied_format", 1, "it_worked_app_if" );

expected_format('json');
handle_request( "/test app implied_format (app) invalid" , "/test/app/implied_format.json", 1, undef, expected_error => 404 );
# 10

# test all formats
DW::Routing->register_string( "/test/app/all_format", \&handler, app => 1, args => "it_worked_app_af", formats => 1 );

expected_format('html');
handle_request( "/test app implied_format (app)" , "/test/app/all_format", 1, "it_worked_app_af" ); # 3 tests

expected_format('json');
handle_request( "/test app implied_format (app)" , "/test/app/all_format.json", 1, "it_worked_app_af" ); # 3 test
# 12
