# t/routing-roles-regex.t
#
# Routing tests: Regex roles
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
use DW::Routing::Test tests => 30;

expected_format('html');

begin_tests();

DW::Routing->register_regex( qr !^/r/app(/.+)$!, \&regex_handler, app => 1, args => ["/test", "it_worked_app"], formats => [ 'html', 'format' ] );

expected_format('html');
handle_request( "/r/app (app)" , "/r/app/test", 1, "it_worked_app" ); # 3 tests
handle_request( "/r/app (ssl)" , "/r/app/test", 1, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/r/app (user)", "/r/app/test", 0, "it_worked_app", username => 'test' ); # 1 test

expected_format('format');
handle_request( "/r/app (app)" , "/r/app/test.format", 1, "it_worked_app" ); # 3 tests
handle_request( "/r/app (ssl)" , "/r/app/test.format", 1, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/r/app (user)", "/r/app/test.format", 0, "it_worked_app", username => 'test' ); # 1 test
# 6

DW::Routing->register_regex( qr !^/r/user(/.+)$!, \&regex_handler, user => 1, args => ["/test", "it_worked_user"], formats => [ 'html', 'format' ] );

expected_format('html');
handle_request( "/r/user (app)" , "/r/user/test", 0, "it_worked_user" ); # 1 tests
handle_request( "/r/user (ssl)" , "/r/user/test", 0, "it_worked_user", ssl => 1 ); # 1 test
handle_request( "/r/user (user)", "/r/user/test", 1, "it_worked_user", username => 'test' ); # 3 tests

expected_format('format');
handle_request( "/r/user (app)" , "/r/user/test.format", 0, "it_worked_user" ); # 1 tests
handle_request( "/r/user (ssl)" , "/r/user/test.format", 0, "it_worked_user", ssl => 1 ); # 1 test
handle_request( "/r/user (user)", "/r/user/test.format", 1, "it_worked_user", username => 'test' ); # 3 tests
# 12

DW::Routing->register_regex( qr !^/r/multi(/.+)$!, \&regex_handler, app => 1, args => ["/test", "it_worked_app"], formats => [ 'html', 'format' ] );
DW::Routing->register_regex( qr !^/r/multi(/.+)$!, \&regex_handler, user => 1, args => ["/test", "it_worked_user"], formats => [ 'html', 'format' ] );

expected_format('html');
handle_request( "/r/multi (app)" , "/r/multi/test", 1, "it_worked_app" ); # 3 tests
handle_request( "/r/multi (ssl)" , "/r/multi/test", 1, "it_worked_app", ssl => 1 ); # 3 tests
handle_request( "/r/multi (user)", "/r/multi/test", 1, "it_worked_user", username => 'test' ); # 3 tests

expected_format('format');
handle_request( "/r/multi (app)" , "/r/multi/test.format", 1, "it_worked_app" ); # 3 tests
handle_request( "/r/multi (ssl)" , "/r/multi/test.format", 1, "it_worked_app", ssl => 1 ); # 3 tests
handle_request( "/r/multi (user)", "/r/multi/test.format", 1, "it_worked_user", username => 'test' ); # 3 tests
# 18

DW::Routing->register_regex( qr !^/r/all(/.+)$!, \&regex_handler, app => 1, user => 1, format => 'html', args => ["/test", "it_worked_all"], formats => [ 'html', 'format' ] );

expected_format('html');
handle_request( "/r/all (app)" , "/r/all/test", 1, "it_worked_all" ); # 3 tests
handle_request( "/r/all (ssl)" , "/r/all/test", 1, "it_worked_all", ssl => 1 ); # 3 tests
handle_request( "/r/all (user)", "/r/all/test", 1, "it_worked_all", username => 'test' ); # 3 tests

expected_format('format');
handle_request( "/r/all (app)" , "/r/all/test.format", 1, "it_worked_all" ); # 3 tests
handle_request( "/r/all (ssl)" , "/r/all/test.format", 1, "it_worked_all", ssl => 1 ); # 3 tests
handle_request( "/r/all (user)", "/r/all/test.format", 1, "it_worked_all", username => 'test' ); # 3 tests
# 24

DW::Routing->register_regex( qr !^/r/app_implicit(/.+)$!, \&regex_handler, args => ["/test", "it_worked_app"], formats => [ 'html', 'format' ] );

expected_format('html');
handle_request( "/r/app_implicit (app)" , "/r/app_implicit/test", 1, "it_worked_app" ); # 3 tests
handle_request( "/r/app_implicit (ssl)" , "/r/app_implicit/test", 1, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/r/app_implicit (user)", "/r/app_implicit/test", 0, "it_worked_app", username => 'test' ); # 1 test

expected_format('format');
handle_request( "/r/app_implicit (app)" , "/r/app_implicit/test.format", 1, "it_worked_app" ); # 3 tests
handle_request( "/r/app_implicit (ssl)" , "/r/app_implicit/test.format", 1, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/r/app_implicit (user)", "/r/app_implicit/test.format", 0, "it_worked_app", username => 'test' ); # 1 test
# 30
