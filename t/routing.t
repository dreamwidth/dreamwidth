# -*-perl-*-
use strict;
use Test::More tests => 294;
use lib "$ENV{LJHOME}/cgi-bin";
require 'ljlib.pl';
use DW::Routing::Apache2;
use Apache2::Const qw/ :common REDIRECT HTTP_NOT_MODIFIED
                       HTTP_MOVED_PERMANENTLY HTTP_MOVED_TEMPORARILY
                       M_TRACE M_OPTIONS /;

my $result;
my $expected_format = 'html';
my $__name;

handle_request( "foo", "/foo", 0, 0 ); # 1 test
handle_request( "foo", "/foo.format", 0, 0 ); # 1 test
# 2

DW::Routing::Apache2->register_string( "/test/app", \&handler, app => 1, args => "it_worked_app" );

$expected_format = 'html';
handle_request( "/test app (app)" , "/test/app", 1, "it_worked_app" ); # 6 tests
handle_request( "/test app (ssl)" , "/test/app", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/test app (user)", "/test/app", 0, "it_worked_app", username => 'test' ); # 1 test
# 10

$expected_format = 'format';
handle_request( "/test app (app)" , "/test/app.format", 1, "it_worked_app" ); # 6 tests
handle_request( "/test app (ssl)" , "/test/app.format", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/test app (user)", "/test/app.format", 0, "it_worked_app", username => 'test' ); # 1 test
# 18

DW::Routing::Apache2->register_string( "/test/ssl", \&handler, ssl => 1, app => 0, args => "it_worked_ssl" );

$expected_format = 'html';
handle_request( "/test ssl (app)" , "/test/ssl", 0, "it_worked_ssl" ); # 1 tests
handle_request( "/test ssl (ssl)" , "/test/ssl", 1, "it_worked_ssl", ssl => 1 ); # 1 test
handle_request( "/test ssl (user)", "/test/ssl", 0, "it_worked_ssl", username => 'test' ); # 6 tests
# 26

$expected_format = 'format';
handle_request( "/test ssl (app)" , "/test/ssl.format", 0, "it_worked_ssl" ); # 1 tests
handle_request( "/test ssl (ssl)" , "/test/ssl.format", 1, "it_worked_ssl", ssl => 1 ); # 1 test
handle_request( "/test ssl (user)", "/test/ssl.format", 0, "it_worked_ssl", username => 'test' ); # 6 tests
# 34

DW::Routing::Apache2->register_string( "/test/user", \&handler, user => 1, args => "it_worked_user" );

$expected_format = 'html';
handle_request( "/test user (app)" , "/test/user", 0, "it_worked_user" ); # 1 tests
handle_request( "/test user (ssl)" , "/test/user", 0, "it_worked_user", ssl => 1 ); # 1 test
handle_request( "/test user (user)", "/test/user", 1, "it_worked_user", username => 'test' ); # 6 tests
# 42

$expected_format = 'format';
handle_request( "/test user (app)" , "/test/user.format", 0, "it_worked_user" ); # 1 tests
handle_request( "/test user (ssl)" , "/test/user.format", 0, "it_worked_user", ssl => 1 ); # 1 test
handle_request( "/test user (user)", "/test/user.format", 1, "it_worked_user", username => 'test' ); # 6 tests
# 50

DW::Routing::Apache2->register_string( "/test", \&handler, app => 1, args => "it_worked_app" );
DW::Routing::Apache2->register_string( "/test", \&handler, ssl => 1, app => 0, args => "it_worked_ssl" );
DW::Routing::Apache2->register_string( "/test", \&handler, user => 1, args => "it_worked_user" );

$expected_format = 'html';
handle_request( "/test multi (app)" , "/test", 1, "it_worked_app" ); # 6 tests
handle_request( "/test multi (ssl)" , "/test", 1, "it_worked_ssl", ssl => 1 ); # 6 tests
handle_request( "/test multi (user)", "/test", 1, "it_worked_user", username => 'test' ); # 6 tests
# 68

$expected_format = 'format';
handle_request( "/test multi (app)" , "/test.format", 1, "it_worked_app" ); # 6 tests
handle_request( "/test multi (ssl)" , "/test.format", 1, "it_worked_ssl", ssl => 1 ); # 6 tests
handle_request( "/test multi (user)", "/test.format", 1, "it_worked_user", username => 'test' ); # 6 tests
# 86

DW::Routing::Apache2->register_string( "/test/all", \&handler, app => 1, user => 1, ssl => 1, format => 'json', args => "it_worked_multi" );

$expected_format = 'json';
handle_request( "/test all (app)" , "/test/all", 1, "it_worked_multi"); # 6 tests
handle_request( "/test all (ssl)" , "/test/all", 1, "it_worked_multi", ssl => 1 ); # 6 tests
handle_request( "/test all (user)", "/test/all", 1, "it_worked_multi", username => 'test' ); # 6 tests
# 104

$expected_format = 'format';
handle_request( "/test all (app)" , "/test/all.format", 1, "it_worked_multi"); # 6 tests
handle_request( "/test all (ssl)" , "/test/all.format", 1, "it_worked_multi", ssl => 1 ); # 6 tests
handle_request( "/test all (user)", "/test/all.format", 1, "it_worked_multi", username => 'test' ); # 6 tests
# 122

DW::Routing::Apache2->register_regex( qr !^/r/app(/.+)$!, \&regex_handler, app => 1, args => ["/test", "it_worked_app"] );

$expected_format = 'html';
handle_request( "/r/app (app)" , "/r/app/test", 1, "it_worked_app" ); # 6 tests
handle_request( "/r/app (ssl)" , "/r/app/test", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/r/app (user)", "/r/app/test", 0, "it_worked_app", username => 'test' ); # 1 test
# 130

$expected_format = 'format';
handle_request( "/r/app (app)" , "/r/app/test.format", 1, "it_worked_app" ); # 6 tests
handle_request( "/r/app (ssl)" , "/r/app/test.format", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/r/app (user)", "/r/app/test.format", 0, "it_worked_app", username => 'test' ); # 1 test
# 138

DW::Routing::Apache2->register_regex( qr !^/r/ssl(/.+)$!, \&regex_handler, ssl => 1, app => 0, args => ["/test", "it_worked_ssl"] );

$expected_format = 'html';
handle_request( "/r/ssl (app)" , "/r/ssl/test", 0, "it_worked_ssl" ); # 1 tests
handle_request( "/r/ssl (ssl)" , "/r/ssl/test", 1, "it_worked_ssl", ssl => 1 ); # 6 test
handle_request( "/r/ssl (user)", "/r/ssl/test", 0, "it_worked_ssl", username => 'test' ); # 1 test
# 146

$expected_format = 'format';
handle_request( "/r/ssl (app)" , "/r/ssl/test.format", 0, "it_worked_ssl" ); # 1 tests
handle_request( "/r/ssl (ssl)" , "/r/ssl/test.format", 1, "it_worked_ssl", ssl => 1 ); # 6 test
handle_request( "/r/ssl (user)", "/r/ssl/test.format", 0, "it_worked_ssl", username => 'test' ); # 1 test
# 154

DW::Routing::Apache2->register_regex( qr !^/r/user(/.+)$!, \&regex_handler, user => 1, args => ["/test", "it_worked_user"] );

$expected_format = 'html';
handle_request( "/r/user (app)" , "/r/user/test", 0, "it_worked_user" ); # 1 tests
handle_request( "/r/user (ssl)" , "/r/user/test", 0, "it_worked_user", ssl => 1 ); # 1 test
handle_request( "/r/user (user)", "/r/user/test", 1, "it_worked_user", username => 'test' ); # 6 test
# 162

$expected_format = 'format';
handle_request( "/r/user (app)" , "/r/user/test.format", 0, "it_worked_user" ); # 1 tests
handle_request( "/r/user (ssl)" , "/r/user/test.format", 0, "it_worked_user", ssl => 1 ); # 1 test
handle_request( "/r/user (user)", "/r/user/test.format", 1, "it_worked_user", username => 'test' ); # 6 test
# 170

DW::Routing::Apache2->register_regex( qr !^/r/multi(/.+)$!, \&regex_handler, app => 1, args => ["/test", "it_worked_app"] );
DW::Routing::Apache2->register_regex( qr !^/r/multi(/.+)$!, \&regex_handler, ssl => 1, app => 0, args => ["/test", "it_worked_ssl"] );
DW::Routing::Apache2->register_regex( qr !^/r/multi(/.+)$!, \&regex_handler, user => 1, args => ["/test", "it_worked_user"] );

$expected_format = 'html';
handle_request( "/r/multi (app)" , "/r/multi/test", 1, "it_worked_app" ); # 6 test
handle_request( "/r/multi (ssl)" , "/r/multi/test", 1, "it_worked_ssl", ssl => 1 ); # 6 test
handle_request( "/r/multi (user)", "/r/multi/test", 1, "it_worked_user", username => 'test' ); # 6 test
# 188

$expected_format = 'format';
handle_request( "/r/multi (app)" , "/r/multi/test.format", 1, "it_worked_app" ); # 6 tests
handle_request( "/r/multi (ssl)" , "/r/multi/test.format", 1, "it_worked_ssl", ssl => 1 ); # 6 test
handle_request( "/r/multi (user)", "/r/multi/test.format", 1, "it_worked_user", username => 'test' ); # 6 test
# 206

DW::Routing::Apache2->register_regex( qr !^/r/all(/.+)$!, \&regex_handler, app => 1, user => 1, ssl => 1, format => 'json', args => ["/test", "it_worked_all"] );

$expected_format = 'json';
handle_request( "/r/all (app)" , "/r/all/test", 1, "it_worked_all" ); # 6 test
handle_request( "/r/all (ssl)" , "/r/all/test", 1, "it_worked_all", ssl => 1 ); # 6 test
handle_request( "/r/all (user)", "/r/all/test", 1, "it_worked_all", username => 'test' ); # 6 test
# 224

$expected_format = 'format';
handle_request( "/r/all (app)" , "/r/all/test.format", 1, "it_worked_all" ); # 6 tests
handle_request( "/r/all (ssl)" , "/r/all/test.format", 1, "it_worked_all", ssl => 1 ); # 6 test
handle_request( "/r/all (user)", "/r/all/test.format", 1, "it_worked_all", username => 'test' ); # 6 test
# 242

DW::Routing::Apache2->register_string( "/test/app_implicit", \&handler, args => "it_worked_app" );

$expected_format = 'html';
handle_request( "/test appapp_implicit (app)" , "/test/app_implicit", 1, "it_worked_app" ); # 6 tests
handle_request( "/test appapp_implicit (ssl)" , "/test/app_implicit", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/test appapp_implicit (user)", "/test/app_implicit", 0, "it_worked_app", username => 'test' ); # 1 test
# 250

$expected_format = 'format';
handle_request( "/test appapp_implicit (app)" , "/test/app_implicit.format", 1, "it_worked_app" ); # 6 tests
handle_request( "/test appapp_implicit (ssl)" , "/test/app_implicit.format", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/test appapp_implicit (user)", "/test/app_implicit.format", 0, "it_worked_app", username => 'test' ); # 1 test
# 258

DW::Routing::Apache2->register_regex( qr !^/r/app_implicit(/.+)$!, \&regex_handler, args => ["/test", "it_worked_app"] );

$expected_format = 'html';
handle_request( "/r/app_implicit (app)" , "/r/app_implicit/test", 1, "it_worked_app" ); # 6 tests
handle_request( "/r/app_implicit (ssl)" , "/r/app_implicit/test", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/r/app_implicit (user)", "/r/app_implicit/test", 0, "it_worked_app", username => 'test' ); # 1 test
# 266

$expected_format = 'format';
handle_request( "/r/app_implicit (app)" , "/r/app_implicit/test.format", 1, "it_worked_app" ); # 6 tests
handle_request( "/r/app_implicit (ssl)" , "/r/app_implicit/test.format", 0, "it_worked_app", ssl => 1 ); # 1 test
handle_request( "/r/app_implicit (user)", "/r/app_implicit/test.format", 0, "it_worked_app", username => 'test' ); # 1 test
# 274

sub handle_request {
    my ( $name, $uri, $valid, $expected, %opts ) = @_;
    my $r = DummyRequest->new( $uri );
    $result = undef;
    $__name = $name;

    my $ret = DW::Routing::Apache2->call( $r, %opts );
    if ( ! $valid ) {
        is( $ret, undef, "$name: wrong return" );
        return 1;
    }
    is( $ret, OK, "$name: wrong return" );
    if ( ! defined $ret || $ret != OK ) {
        return 0;
    }
    is ( $r->{handler}, 'perl-script', "$name: wrong handler type" );
    is ( ref $r->{perl_handler}, 'CODE',  "$name: handler missing/incorrect" );
    if ( ref $r->{perl_handler} ne 'CODE' ) {
        return;
    }
    $ret = $r->{perl_handler}->($r);
    is( $ret, OK, "$name: wrong return (from perl handler)" );
    if ( $ret != OK ) {
        return 0;
    }
    is ( $result, $expected, "$name: handler set wrong value.");
}

sub handler {
    $result = $_[0]->args;
    is ( $_[0]->format, $expected_format, "$__name: format wrong!" );
    return OK;
}

sub regex_handler {
    $result = $_[0]->args->[1];
    is ( $_[0]->format, $expected_format, "$__name: format wrong!" );
    is( $_[0]->subpatterns->[0], $_[0]->args->[0], "$__name: capture wrong!" );
    return OK;
}

# This is sorta hackish, but we need something that pretends to be
# an Apache2 request enough to at least allow DW::Routing::Apache2 to work
package DummyRequest;

sub new {
    my ($class, $uri) = @_;
    
    return bless({ uri => $uri, handler => '', perl_handler => undef, pnotes => {}, notes => {} }, $class);
}

sub uri { return $_[0]->{uri}; }
sub handler { $_[0]->{handler} = $_[1]; }
sub pnotes { return $_[0]->{pnotes}; }
sub notes { return $_[0]->{notes}; }
sub content_type { }
sub status { }
sub push_handlers {
    $_[0]->{perl_handler} = $_[2] if $_[1] eq 'PerlResponseHandler';
}
