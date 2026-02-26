#!/usr/bin/perl
# t/plack-request.t
#
# Test DW::Request::Plack methods — the Plack-specific request/response
# abstraction layer.  Covers every method implemented in Plack.pm plus
# key inherited Base methods exercised through the Plack path.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use v5.10;

use Test::More tests => 23;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

use DW::Request::Plack;
use HTTP::Headers;

# Helper to build a minimal PSGI env and return a fresh DW::Request::Plack.
# Accepts overrides merged on top of the base env.  To supply a request body,
# pass _body => "string" (it will be turned into a psgi.input filehandle and
# CONTENT_LENGTH will be set automatically).
sub make_request {
    my (%overrides) = @_;

    # Pull out the synthetic _body key before it lands in the env hash
    my $body = delete $overrides{_body} // '';

    open my $input, '<', \$body or die "open scalar: $!";

    my $env = {
        'REQUEST_METHOD'    => 'GET',
        'PATH_INFO'         => '/',
        'QUERY_STRING'      => '',
        'SERVER_NAME'       => 'www.example.com',
        'SERVER_PORT'       => 80,
        'HTTP_HOST'         => 'www.example.com',
        'SCRIPT_NAME'       => '',
        'CONTENT_LENGTH'    => length($body),
        'psgi.version'      => [ 1, 1 ],
        'psgi.url_scheme'   => 'http',
        'psgi.input'        => $input,
        'psgi.errors'       => do { open my $fh, '>', \( my $x = '' ); $fh },
        'psgi.multithread'  => 0,
        'psgi.multiprocess' => 1,
        'psgi.run_once'     => 0,
        'psgi.nonblocking'  => 0,
        'psgi.streaming'    => 1,
        %overrides,
    };

    DW::Request->reset;
    return DW::Request::Plack->new($env);
}

###########################################################################
# 1. uri — must return path only, not full URL
###########################################################################

subtest 'uri returns path only' => sub {
    plan tests => 4;

    my $r = make_request( 'PATH_INFO' => '/some/page' );
    is( $r->uri, '/some/page', 'basic path' );

    $r = make_request( 'PATH_INFO' => '/search', 'QUERY_STRING' => 'q=hello' );
    is( $r->uri, '/search', 'path without query string' );

    $r = make_request( 'PATH_INFO' => '' );
    is( $r->uri, '/', 'empty path falls back to /' );

    $r = make_request( 'PATH_INFO' => '/a/b/c' );
    unlike( $r->uri, qr/^https?:/, 'uri never returns a full URL' );
};

###########################################################################
# 2. method / query_string pass-throughs
###########################################################################

subtest 'method and query_string pass-throughs' => sub {
    plan tests => 3;

    my $r = make_request(
        'REQUEST_METHOD' => 'POST',
        'QUERY_STRING'   => 'foo=1&bar=2',
    );

    is( $r->method,       'POST',        'method returns REQUEST_METHOD' );
    is( $r->query_string, 'foo=1&bar=2', 'query_string returns QUERY_STRING' );

    $r = make_request( 'REQUEST_METHOD' => 'GET' );
    is( $r->method, 'GET', 'GET method' );
};

###########################################################################
# 3. header_in — read request headers
###########################################################################

subtest 'header_in reads request headers' => sub {
    plan tests => 3;

    my $r = make_request(
        'HTTP_ACCEPT'   => 'text/html',
        'HTTP_X_CUSTOM' => 'foobar',
    );

    is( $r->header_in('Accept'),    'text/html', 'standard header' );
    is( $r->header_in('X-Custom'),  'foobar',    'custom header' );
    is( $r->header_in('X-Missing'), undef,       'missing header returns undef' );
};

###########################################################################
# 4. headers_in — flat key-value list for all request headers
###########################################################################

subtest 'headers_in returns flat key-value list' => sub {
    plan tests => 3;

    my $r = make_request(
        'HTTP_HOST'            => 'www.example.com',
        'HTTP_ACCEPT_LANGUAGE' => 'en-US',
        'HTTP_X_CUSTOM'        => 'testval',
    );

    my %headers = $r->headers_in;

    is( $headers{'Host'},            'www.example.com', 'Host header extracted' );
    is( $headers{'Accept-Language'}, 'en-US',           'Accept-Language header extracted' );
    is( $headers{'X-Custom'},        'testval',         'Custom header extracted' );
};

subtest 'headers_in works with HTTP::Headers->new' => sub {
    plan tests => 2;

    my $r = make_request( 'HTTP_HOST' => 'www.example.com' );

    # This is how XMLRPCTransport.pm uses it (line 57)
    my $h = HTTP::Headers->new( $r->headers_in );
    isa_ok( $h, 'HTTP::Headers' );
    is( $h->header('Host'), 'www.example.com', 'HTTP::Headers created from headers_in' );
};

subtest 'headers_in can be used as hashref via anonymous hash' => sub {
    plan tests => 1;

    my $r = make_request( 'HTTP_REFERER' => 'http://example.com/page' );

    # This is how DW::Controller::Manage::Tracking uses it
    my $referer = { $r->headers_in }->{'Referer'};
    is( $referer, 'http://example.com/page', 'hashref dereference works' );
};

###########################################################################
# 5. header_out / header_out_add / err_header_out
###########################################################################

subtest 'header_out and header_out_add' => sub {
    plan tests => 4;

    my $r = make_request();

    # setter then getter
    $r->header_out( 'X-Foo' => 'bar' );
    is( $r->header_out('X-Foo'), 'bar', 'header_out set/get' );

    # replace
    $r->header_out( 'X-Foo' => 'baz' );
    is( $r->header_out('X-Foo'), 'baz', 'header_out replaces value' );

    # err_header_out is aliased
    $r->err_header_out( 'X-Err' => 'yes' );
    is( $r->err_header_out('X-Err'), 'yes', 'err_header_out alias works' );

    # header_out_add appends (needed for multiple Set-Cookie)
    $r->header_out( 'Set-Cookie' => 'a=1' );
    $r->header_out_add( 'Set-Cookie' => 'b=2' );
    $r->status(200);
    my $res = $r->res;

    # finalize returns [status, [header_pairs], body]
    my @hdrs = @{ $res->[1] };
    my @cookies;
    while ( my ( $k, $v ) = splice( @hdrs, 0, 2 ) ) {
        push @cookies, $v if lc($k) eq 'set-cookie';
    }
    is( scalar @cookies, 2, 'header_out_add appends rather than replaces' );
};

###########################################################################
# 6. status / status_line
###########################################################################

subtest 'status getter/setter' => sub {
    plan tests => 2;

    my $r = make_request();

    $r->status(201);
    is( $r->status, 201, 'status set to 201' );

    $r->status(404);
    is( $r->status, 404, 'status updated to 404' );
};

subtest 'status_line sets status from numeric code' => sub {
    plan tests => 2;

    my $r = make_request();

    $r->status_line(404);
    is( $r->status, 404, 'status_line(404) sets status to 404' );

    $r->status_line(200);
    is( $r->status, 200, 'status_line(200) sets status to 200' );
};

subtest 'status_line parses numeric prefix from status string' => sub {
    plan tests => 2;

    my $r = make_request();

    # SOAP::Lite response->code returns things like "200 OK"
    $r->status_line("200 OK");
    is( $r->status, 200, 'status_line("200 OK") sets status to 200' );

    $r->status_line("500 Internal Server Error");
    is( $r->status, 500, 'status_line("500 Internal...") sets status to 500' );
};

###########################################################################
# 7. content_type — getter reads request, setter writes response
###########################################################################

subtest 'content_type dual getter/setter' => sub {
    plan tests => 2;

    my $r = make_request( 'CONTENT_TYPE' => 'application/json' );

    # getter reads from request
    is( $r->content_type, 'application/json', 'getter reads request content type' );

    # setter writes to response (and returns the value)
    $r->content_type('text/html');
    $r->status(200);
    my $res = $r->res;

    # check response headers for content-type
    my @hdrs = @{ $res->[1] };
    my $ct;
    while ( my ( $k, $v ) = splice( @hdrs, 0, 2 ) ) {
        $ct = $v if lc($k) eq 'content-type';
    }
    is( $ct, 'text/html', 'setter writes response content type' );
};

###########################################################################
# 8. content — raw request body
###########################################################################

subtest 'content returns raw request body' => sub {
    plan tests => 2;

    my $body = '{"hello":"world"}';
    my $r    = make_request(
        'REQUEST_METHOD' => 'POST',
        'CONTENT_TYPE'   => 'application/json',
        _body            => $body,
    );

    is( $r->content, $body, 'content returns POST body' );

    # empty body on GET
    my $r2 = make_request();
    is( $r2->content, '', 'content returns empty string for bodyless GET' );
};

###########################################################################
# 9. address — with proxy override
###########################################################################

subtest 'address with proxy override' => sub {
    plan tests => 3;

    my $r = make_request( 'REMOTE_ADDR' => '10.0.0.1' );

    is( $r->address, '10.0.0.1', 'address returns REMOTE_ADDR' );

    # override for proxy scenario
    $r->address('203.0.113.5');
    is( $r->address, '203.0.113.5', 'address returns override when set' );

    # get_remote_ip delegates to address
    is( $r->get_remote_ip, '203.0.113.5', 'get_remote_ip delegates to address' );
};

###########################################################################
# 10. host
###########################################################################

subtest 'host returns Host header' => sub {
    plan tests => 1;

    my $r = make_request( 'HTTP_HOST' => 'site.example.org' );
    is( $r->host, 'site.example.org', 'host reads HTTP_HOST' );
};

###########################################################################
# 11. path / query_parameters
###########################################################################

subtest 'path and query_parameters' => sub {
    plan tests => 2;

    my $r = make_request(
        'PATH_INFO'    => '/test/path',
        'QUERY_STRING' => 'color=red&size=large',
    );

    is( $r->path, '/test/path', 'path returns PATH_INFO' );

    my $params = $r->query_parameters;
    is( $params->{color}, 'red', 'query_parameters parses QUERY_STRING' );
};

###########################################################################
# 12. print / res — body accumulation and response finalization
###########################################################################

subtest 'print accumulates body, res finalizes PSGI response' => sub {
    plan tests => 5;

    my $r = make_request();
    $r->status(200);
    $r->content_type('text/plain');

    $r->print("Hello, ");
    $r->print("world!");

    my $res = $r->res;

    # PSGI response triplet: [status, [headers], body]
    is( ref $res,      'ARRAY', 'res returns an array ref' );
    is( $res->[0],     200,     'status in response triplet' );
    is( ref $res->[1], 'ARRAY', 'headers is an array ref' );

    # body should contain both chunks
    my $body = join '', @{ $res->[2] };
    is( $body, 'Hello, world!', 'body contains accumulated prints' );

    # content-length should reflect total length
    my @hdrs = @{ $res->[1] };
    my $cl;
    while ( my ( $k, $v ) = splice( @hdrs, 0, 2 ) ) {
        $cl = $v if lc($k) eq 'content-length';
    }
    is( $cl, length('Hello, world!'), 'content-length is set correctly' );
};

subtest 'res with no body omits content-length' => sub {
    plan tests => 1;

    my $r = make_request();
    $r->status(204);

    my $res  = $r->res;
    my @hdrs = @{ $res->[1] };
    my $cl;
    while ( my ( $k, $v ) = splice( @hdrs, 0, 2 ) ) {
        $cl = $v if lc($k) eq 'content-length';
    }
    is( $cl, undef, 'no content-length when body was never written' );
};

###########################################################################
# 13. redirect — 303, preserves existing headers, clears body
###########################################################################

subtest 'redirect returns 303 and preserves existing headers' => sub {
    plan tests => 5;

    my $r = make_request();

    # Set a cookie before redirecting (the login flow does this)
    $r->header_out( 'Set-Cookie' => 'session=abc123' );
    $r->print("this should be cleared");

    my $res = $r->redirect('http://example.com/destination');

    is( $res->[0], 303, 'redirect uses 303 status' );

    my @hdrs = @{ $res->[1] };
    my ( $location, $cookie, $cl );
    while ( my ( $k, $v ) = splice( @hdrs, 0, 2 ) ) {
        $location = $v if lc($k) eq 'location';
        $cookie   = $v if lc($k) eq 'set-cookie';
        $cl       = $v if lc($k) eq 'content-length';
    }

    is( $location, 'http://example.com/destination', 'Location header set' );
    is( $cookie, 'session=abc123', 'pre-existing Set-Cookie preserved' );

    # body should have been cleared
    ok( !defined $res->[2] || !length( join '', @{ $res->[2] || [] } ),
        'body cleared after redirect' );

    # content-length should not reflect the old body
    ok( !$cl || $cl == 0, 'content-length is 0 or absent after redirect' );
};

###########################################################################
# 14. set_last_modified / meets_conditions — 304 logic
###########################################################################

subtest 'meets_conditions returns 304 when not modified' => sub {
    plan tests => 4;

    # No If-Modified-Since header → 0 (proceed)
    my $r = make_request();
    $r->set_last_modified(1000000);
    is( $r->meets_conditions, 0, 'no IMS header → 0' );

    # IMS in the future → not modified → 304
    $r = make_request( 'HTTP_IF_MODIFIED_SINCE' => 'Sun, 01 Jan 2034 00:00:00 GMT', );
    $r->set_last_modified(1000000);    # way in the past
    is( $r->meets_conditions, 304, 'IMS after Last-Modified → 304' );

    # IMS in the past → modified → 0
    $r = make_request( 'HTTP_IF_MODIFIED_SINCE' => 'Mon, 01 Jan 2001 00:00:00 GMT', );
    $r->set_last_modified( time() );
    is( $r->meets_conditions, 0, 'IMS before Last-Modified → 0' );

    # No Last-Modified set → 0
    $r = make_request( 'HTTP_IF_MODIFIED_SINCE' => 'Sun, 01 Jan 2034 00:00:00 GMT', );
    is( $r->meets_conditions, 0, 'no Last-Modified set → 0' );
};

###########################################################################
# 15. no_cache — cache-busting headers
###########################################################################

subtest 'no_cache sets cache-busting headers' => sub {
    plan tests => 3;

    my $r = make_request();
    $r->no_cache;

    is(
        $r->header_out('Cache-Control'),
        'no-cache, no-store, must-revalidate',
        'Cache-Control header'
    );
    is( $r->header_out('Pragma'),  'no-cache', 'Pragma header' );
    is( $r->header_out('Expires'), '0',        'Expires header' );
};

###########################################################################
# 16. pnote / note — per-request storage
###########################################################################

subtest 'pnote and note are separate namespaces' => sub {
    plan tests => 5;

    my $r = make_request();

    # set and get
    $r->pnote( 'key1', 'pval' );
    $r->note( 'key1', 'nval' );

    is( $r->pnote('key1'), 'pval', 'pnote stores value' );
    is( $r->note('key1'),  'nval', 'note stores separate value for same key' );

    # unset key returns undef
    is( $r->pnote('missing'), undef, 'pnote returns undef for missing key' );
    is( $r->note('missing'),  undef, 'note returns undef for missing key' );

    # overwrite
    $r->pnote( 'key1', 'updated' );
    is( $r->pnote('key1'), 'updated', 'pnote overwrites previous value' );
};

###########################################################################
# 17. did_post / post_args / get_args — Base methods through Plack
###########################################################################

subtest 'did_post, post_args, and get_args through Plack' => sub {
    plan tests => 6;

    # GET request
    my $r = make_request( 'QUERY_STRING' => 'color=blue&size=10' );
    ok( !$r->did_post, 'GET request: did_post is false' );

    my $get_args = $r->get_args;
    is( $get_args->{color}, 'blue', 'get_args parses color' );
    is( $get_args->{size},  '10',   'get_args parses size' );

    # POST request with form body
    my $post_body = 'username=testuser&action=login';
    $r = make_request(
        'REQUEST_METHOD' => 'POST',
        'CONTENT_TYPE'   => 'application/x-www-form-urlencoded',
        _body            => $post_body,
    );
    ok( $r->did_post, 'POST request: did_post is true' );

    my $post_args = $r->post_args;
    is( $post_args->{username}, 'testuser', 'post_args parses username' );
    is( $post_args->{action},   'login',    'post_args parses action' );
};

###########################################################################
# 18. XMLRPCTransport->handler — regression test for headers_in / status_line
#     The handler crashed with "Can't locate object method 'headers_in'"
#     before these methods were added to DW::Request::Plack.
###########################################################################

subtest 'XMLRPCTransport handler works under Plack' => sub {
    plan tests => 3;

    use DW::Request::XMLRPCTransport;

    # Minimal XMLRPC request — calls LJ.XMLRPC.getchallenge which needs
    # no authentication or database.  Even if the dispatch fails, the test
    # verifies that the transport layer (headers_in, status_line, header_out,
    # content_type, print) all work without dying.
    my $xmlrpc_body = <<'XMLRPC';
<?xml version="1.0"?>
<methodCall>
  <methodName>LJ.XMLRPC.getchallenge</methodName>
  <params/>
</methodCall>
XMLRPC

    my $r = make_request(
        'REQUEST_METHOD' => 'POST',
        'PATH_INFO'      => '/interface/xmlrpc',
        'CONTENT_TYPE'   => 'text/xml',
        'HTTP_HOST'      => 'www.example.com',
        _body            => $xmlrpc_body,
    );

    # Call the handler — this is the code path that was crashing.
    # The XMLRPC dispatch may succeed or fail depending on what LJ::XMLRPC
    # does, but the transport layer itself must not die.
    my $server;
    eval { $server = DW::Request::XMLRPCTransport->dispatch_to('LJ::XMLRPC')->handle(); };
    ok( !$@, 'XMLRPCTransport->handle() does not die under Plack' )
        or diag("Error: $@");

    # The handler should have written a response via $r->print / status_line
    ok( defined $r->status, 'status was set on the response' );

    # Response body should be non-empty XML (either a result or a fault)
    $r->status( $r->status || 200 );    # ensure status for finalize
    my $res  = $r->res;
    my $body = join '', @{ $res->[2] || [] };
    ok( length($body) > 0, 'response body is non-empty' );
};
