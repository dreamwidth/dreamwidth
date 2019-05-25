# t/routing-roles-string.t
#
# Routing tests: String roles
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
use DW::Routing::Test tests => 30;

expected_format('html');

begin_tests();

DW::Routing->register_string(
    "/test/app", \&handler,
    app     => 1,
    args    => "it_worked_app",
    formats => [ 'html', 'format' ]
);

handle_request( "/test app (app)",  "/test/app", 1, "it_worked_app" );
handle_request( "/test app (ssl)",  "/test/app", 1, "it_worked_app", ssl => 1 );
handle_request( "/test app (user)", "/test/app", 0, "it_worked_app", username => 'test' );

expected_format('format');
handle_request( "/test app (app)",  "/test/app.format", 1, "it_worked_app" );
handle_request( "/test app (ssl)",  "/test/app.format", 1, "it_worked_app", ssl => 1 );
handle_request( "/test app (user)", "/test/app.format", 0, "it_worked_app", username => 'test' );

# 6

DW::Routing->register_string(
    "/test/user", \&handler,
    user    => 1,
    args    => "it_worked_user",
    formats => [ 'html', 'format' ]
);

expected_format('html');
handle_request( "/test user (app)",  "/test/user", 0, "it_worked_user" );
handle_request( "/test user (ssl)",  "/test/user", 0, "it_worked_user", ssl => 1 );
handle_request( "/test user (user)", "/test/user", 1, "it_worked_user", username => 'test' );

expected_format('format');
handle_request( "/test user (app)",  "/test/user.format", 0, "it_worked_user" );
handle_request( "/test user (ssl)",  "/test/user.format", 0, "it_worked_user", ssl => 1 );
handle_request( "/test user (user)", "/test/user.format", 1, "it_worked_user", username => 'test' );

# 12

DW::Routing->register_string(
    "/test", \&handler,
    app     => 1,
    args    => "it_worked_app",
    formats => [ 'html', 'format' ]
);
DW::Routing->register_string(
    "/test", \&handler,
    user    => 1,
    args    => "it_worked_user",
    formats => [ 'html', 'format' ]
);

expected_format('html');
handle_request( "/test multi (app)",  "/test", 1, "it_worked_app" );
handle_request( "/test multi (ssl)",  "/test", 1, "it_worked_app", ssl => 1 );
handle_request( "/test multi (user)", "/test", 1, "it_worked_user", username => 'test' );

expected_format('format');
handle_request( "/test multi (app)",  "/test.format", 1, "it_worked_app" );
handle_request( "/test multi (ssl)",  "/test.format", 1, "it_worked_app", ssl => 1 );
handle_request( "/test multi (user)", "/test.format", 1, "it_worked_user", username => 'test' );

# 18

DW::Routing->register_string(
    "/test/all", \&handler,
    app     => 1,
    user    => 1,
    ssl     => 1,
    args    => "it_worked_multi",
    formats => [ 'html', 'format' ]
);

expected_format('html');
handle_request( "/test all (app)",  "/test/all", 1, "it_worked_multi" );
handle_request( "/test all (ssl)",  "/test/all", 1, "it_worked_multi", ssl => 1 );
handle_request( "/test all (user)", "/test/all", 1, "it_worked_multi", username => 'test' );

expected_format('format');
handle_request( "/test all (app)",  "/test/all.format", 1, "it_worked_multi" );
handle_request( "/test all (ssl)",  "/test/all.format", 1, "it_worked_multi", ssl => 1 );
handle_request( "/test all (user)", "/test/all.format", 1, "it_worked_multi", username => 'test' );

# 24

DW::Routing->register_string(
    "/test/app_implicit", \&handler,
    args    => "it_worked_app",
    formats => [ 'html', 'format' ]
);

expected_format('html');
handle_request( "/test app_implicit (app)", "/test/app_implicit", 1, "it_worked_app" );
handle_request( "/test app_implicit (ssl)", "/test/app_implicit", 1, "it_worked_app", ssl => 1 );
handle_request( "/test app_implicit (user)",
    "/test/app_implicit", 0, "it_worked_app", username => 'test' );

expected_format('format');
handle_request( "/test app_implicit (app)", "/test/app_implicit.format", 1, "it_worked_app" );
handle_request( "/test app_implicit (ssl)",
    "/test/app_implicit.format", 1, "it_worked_app", ssl => 1 );
handle_request( "/test app_implicit (user)",
    "/test/app_implicit.format", 0, "it_worked_app", username => 'test' );

# 30
