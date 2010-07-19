# -*-perl-*-
use strict;
use Test::More tests => 174;
use lib "$ENV{LJHOME}/cgi-bin";

# don't let DW::Routing load DW::Controller subclasses
$DW::Routing::DONT_LOAD = 1;

require 'ljlib.pl';
use DW::Request::Standard;
use HTTP::Request;
use DW::Routing;

my $result;
my $expected_format = 'html';
my $__name;

handle_request( "foo", "/foo", 0, 0 ); # 1 test
handle_request( "foo", "/foo.format", 0, 0 ); # 1 test
# 2

DW::Routing->register_string( "/test/app", \&handler, app => 1, args => "it_worked_app" );

$expected_format = 'html';
handle_request( "/test app (app)" , "/test/app", 1, "it_worked_app" ); # 3 tests
handle_request( "/test app (ssl)" , "/test/app", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/test app (user)", "/test/app", 0, "it_worked_app", username => 'test' ); # 1 test
# 7

$expected_format = 'format';
handle_request( "/test app (app)" , "/test/app.format", 1, "it_worked_app" ); # 3 tests
handle_request( "/test app (ssl)" , "/test/app.format", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/test app (user)", "/test/app.format", 0, "it_worked_app", username => 'test' ); # 1 test
# 12

DW::Routing->register_string( "/test/ssl", \&handler, ssl => 1, app => 0, args => "it_worked_ssl" );

$expected_format = 'html';
handle_request( "/test ssl (app)" , "/test/ssl", 0, "it_worked_ssl" ); # 1 tests
handle_request( "/test ssl (ssl)" , "/test/ssl", 1, "it_worked_ssl", ssl => 1 ); # 1 test
handle_request( "/test ssl (user)", "/test/ssl", 0, "it_worked_ssl", username => 'test' ); # 3 tests
# 17

$expected_format = 'format';
handle_request( "/test ssl (app)" , "/test/ssl.format", 0, "it_worked_ssl" ); # 1 tests
handle_request( "/test ssl (ssl)" , "/test/ssl.format", 1, "it_worked_ssl", ssl => 1 ); # 1 test
handle_request( "/test ssl (user)", "/test/ssl.format", 0, "it_worked_ssl", username => 'test' ); # 3 tests
# 22

DW::Routing->register_string( "/test/user", \&handler, user => 1, args => "it_worked_user" );

$expected_format = 'html';
handle_request( "/test user (app)" , "/test/user", 0, "it_worked_user" ); # 1 tests
handle_request( "/test user (ssl)" , "/test/user", 0, "it_worked_user", ssl => 1 ); # 1 test
handle_request( "/test user (user)", "/test/user", 1, "it_worked_user", username => 'test' ); # 3 tests
# 27

$expected_format = 'format';
handle_request( "/test user (app)" , "/test/user.format", 0, "it_worked_user" ); # 1 tests
handle_request( "/test user (ssl)" , "/test/user.format", 0, "it_worked_user", ssl => 1 ); # 1 test
handle_request( "/test user (user)", "/test/user.format", 1, "it_worked_user", username => 'test' ); # 3 tests
# 32

DW::Routing->register_string( "/test", \&handler, app => 1, args => "it_worked_app" );
DW::Routing->register_string( "/test", \&handler, ssl => 1, app => 0, args => "it_worked_ssl" );
DW::Routing->register_string( "/test", \&handler, user => 1, args => "it_worked_user" );

$expected_format = 'html';
handle_request( "/test multi (app)" , "/test", 1, "it_worked_app" ); # 3 tests
handle_request( "/test multi (ssl)" , "/test", 1, "it_worked_ssl", ssl => 1 ); # 3 tests
handle_request( "/test multi (user)", "/test", 1, "it_worked_user", username => 'test' ); # 3 tests
# 41

$expected_format = 'format';
handle_request( "/test multi (app)" , "/test.format", 1, "it_worked_app" ); # 3 tests
handle_request( "/test multi (ssl)" , "/test.format", 1, "it_worked_ssl", ssl => 1 ); # 3 tests
handle_request( "/test multi (user)", "/test.format", 1, "it_worked_user", username => 'test' ); # 3 tests
# 50

DW::Routing->register_string( "/test/all", \&handler, app => 1, user => 1, ssl => 1, format => 'json', args => "it_worked_multi" );

$expected_format = 'json';
handle_request( "/test all (app)" , "/test/all", 1, "it_worked_multi"); # 3 tests
handle_request( "/test all (ssl)" , "/test/all", 1, "it_worked_multi", ssl => 1 ); # 3 tests
handle_request( "/test all (user)", "/test/all", 1, "it_worked_multi", username => 'test' ); # 3 tests
# 59

$expected_format = 'format';
handle_request( "/test all (app)" , "/test/all.format", 1, "it_worked_multi"); # 3 tests
handle_request( "/test all (ssl)" , "/test/all.format", 1, "it_worked_multi", ssl => 1 ); # 3 tests
handle_request( "/test all (user)", "/test/all.format", 1, "it_worked_multi", username => 'test' ); # 3 tests
# 68

DW::Routing->register_regex( qr !^/r/app(/.+)$!, \&regex_handler, app => 1, args => ["/test", "it_worked_app"] );

$expected_format = 'html';
handle_request( "/r/app (app)" , "/r/app/test", 1, "it_worked_app" ); # 3 tests
handle_request( "/r/app (ssl)" , "/r/app/test", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/r/app (user)", "/r/app/test", 0, "it_worked_app", username => 'test' ); # 1 test
# 74

$expected_format = 'format';
handle_request( "/r/app (app)" , "/r/app/test.format", 1, "it_worked_app" ); # 3 tests
handle_request( "/r/app (ssl)" , "/r/app/test.format", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/r/app (user)", "/r/app/test.format", 0, "it_worked_app", username => 'test' ); # 1 test
# 79

DW::Routing->register_regex( qr !^/r/ssl(/.+)$!, \&regex_handler, ssl => 1, app => 0, args => ["/test", "it_worked_ssl"] );

$expected_format = 'html';
handle_request( "/r/ssl (app)" , "/r/ssl/test", 0, "it_worked_ssl" ); # 1 tests
handle_request( "/r/ssl (ssl)" , "/r/ssl/test", 1, "it_worked_ssl", ssl => 1 ); # 3 tests
handle_request( "/r/ssl (user)", "/r/ssl/test", 0, "it_worked_ssl", username => 'test' ); # 1 test
# 86

$expected_format = 'format';
handle_request( "/r/ssl (app)" , "/r/ssl/test.format", 0, "it_worked_ssl" ); # 1 tests
handle_request( "/r/ssl (ssl)" , "/r/ssl/test.format", 1, "it_worked_ssl", ssl => 1 ); # 3 tests
handle_request( "/r/ssl (user)", "/r/ssl/test.format", 0, "it_worked_ssl", username => 'test' ); # 1 test
# 92

DW::Routing->register_regex( qr !^/r/user(/.+)$!, \&regex_handler, user => 1, args => ["/test", "it_worked_user"] );

$expected_format = 'html';
handle_request( "/r/user (app)" , "/r/user/test", 0, "it_worked_user" ); # 1 tests
handle_request( "/r/user (ssl)" , "/r/user/test", 0, "it_worked_user", ssl => 1 ); # 1 test
handle_request( "/r/user (user)", "/r/user/test", 1, "it_worked_user", username => 'test' ); # 3 tests
# 98

$expected_format = 'format';
handle_request( "/r/user (app)" , "/r/user/test.format", 0, "it_worked_user" ); # 1 tests
handle_request( "/r/user (ssl)" , "/r/user/test.format", 0, "it_worked_user", ssl => 1 ); # 1 test
handle_request( "/r/user (user)", "/r/user/test.format", 1, "it_worked_user", username => 'test' ); # 3 tests
# 104

DW::Routing->register_regex( qr !^/r/multi(/.+)$!, \&regex_handler, app => 1, args => ["/test", "it_worked_app"] );
DW::Routing->register_regex( qr !^/r/multi(/.+)$!, \&regex_handler, ssl => 1, app => 0, args => ["/test", "it_worked_ssl"] );
DW::Routing->register_regex( qr !^/r/multi(/.+)$!, \&regex_handler, user => 1, args => ["/test", "it_worked_user"] );

$expected_format = 'html';
handle_request( "/r/multi (app)" , "/r/multi/test", 1, "it_worked_app" ); # 3 tests
handle_request( "/r/multi (ssl)" , "/r/multi/test", 1, "it_worked_ssl", ssl => 1 ); # 3 tests
handle_request( "/r/multi (user)", "/r/multi/test", 1, "it_worked_user", username => 'test' ); # 3 tests
# 116

$expected_format = 'format';
handle_request( "/r/multi (app)" , "/r/multi/test.format", 1, "it_worked_app" ); # 3 tests
handle_request( "/r/multi (ssl)" , "/r/multi/test.format", 1, "it_worked_ssl", ssl => 1 ); # 3 tests
handle_request( "/r/multi (user)", "/r/multi/test.format", 1, "it_worked_user", username => 'test' ); # 3 tests
# 128

DW::Routing->register_regex( qr !^/r/all(/.+)$!, \&regex_handler, app => 1, user => 1, ssl => 1, format => 'json', args => ["/test", "it_worked_all"] );

$expected_format = 'json';
handle_request( "/r/all (app)" , "/r/all/test", 1, "it_worked_all" ); # 3 tests
handle_request( "/r/all (ssl)" , "/r/all/test", 1, "it_worked_all", ssl => 1 ); # 3 tests
handle_request( "/r/all (user)", "/r/all/test", 1, "it_worked_all", username => 'test' ); # 3 tests
# 140

$expected_format = 'format';
handle_request( "/r/all (app)" , "/r/all/test.format", 1, "it_worked_all" ); # 3 tests
handle_request( "/r/all (ssl)" , "/r/all/test.format", 1, "it_worked_all", ssl => 1 ); # 3 tests
handle_request( "/r/all (user)", "/r/all/test.format", 1, "it_worked_all", username => 'test' ); # 3 tests
# 152

DW::Routing->register_string( "/test/app_implicit", \&handler, args => "it_worked_app" );

$expected_format = 'html';
handle_request( "/test appapp_implicit (app)" , "/test/app_implicit", 1, "it_worked_app" ); # 3 tests
handle_request( "/test appapp_implicit (ssl)" , "/test/app_implicit", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/test appapp_implicit (user)", "/test/app_implicit", 0, "it_worked_app", username => 'test' ); # 1 test
# 157

$expected_format = 'format';
handle_request( "/test appapp_implicit (app)" , "/test/app_implicit.format", 1, "it_worked_app" ); # 3 tests
handle_request( "/test appapp_implicit (ssl)" , "/test/app_implicit.format", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/test appapp_implicit (user)", "/test/app_implicit.format", 0, "it_worked_app", username => 'test' ); # 1 test
# 162

DW::Routing->register_regex( qr !^/r/app_implicit(/.+)$!, \&regex_handler, args => ["/test", "it_worked_app"] );

$expected_format = 'html';
handle_request( "/r/app_implicit (app)" , "/r/app_implicit/test", 1, "it_worked_app" ); # 3 tests
handle_request( "/r/app_implicit (ssl)" , "/r/app_implicit/test", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/r/app_implicit (user)", "/r/app_implicit/test", 0, "it_worked_app", username => 'test' ); # 1 test
# 168

$expected_format = 'format';
handle_request( "/r/app_implicit (app)" , "/r/app_implicit/test.format", 1, "it_worked_app" ); # 3 tests
handle_request( "/r/app_implicit (ssl)" , "/r/app_implicit/test.format", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/r/app_implicit (user)", "/r/app_implicit/test.format", 0, "it_worked_app", username => 'test' ); # 1 test
# 174

use Data::Dumper;
sub handle_request {
    my ( $name, $uri, $valid, $expected, %opts ) = @_;

    $DW::Request::determined = 0;
    $DW::Request::cur_req = undef;

    my $req = HTTP::Request->new(GET=>"$uri");
    my $r = DW::Request::Standard->new($req);

    $result = undef;
    $__name = $name;

    my $ret = DW::Routing->call( %opts );
    if ( ! $valid ) {
        is( $ret, undef, "$name: wrong return" );
        return 1;
    }

    is( $ret, $r->OK, "$name: wrong return" );
    if ( $ret != $r->OK ) {
        return 0;
    }
    is ( $result, $expected, "$name: handler set wrong value.");
}

sub handler {
    my $r = DW::Request->get;
    $result = $_[0]->args;
    is ( $_[0]->format, $expected_format, "$__name: format wrong!" );
    return $r->OK;
}

sub regex_handler {
    my $r = DW::Request->get;
    $result = $_[0]->args->[1];
    is ( $_[0]->format, $expected_format, "$__name: format wrong!" );
    is( $_[0]->subpatterns->[0], $_[0]->args->[0], "$__name: capture wrong!" );
    return $r->OK;
}
