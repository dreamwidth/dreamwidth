#!/usr/bin/perl
# t/plack-cache-control.t
#
# Tests for the default Cache-Control middleware (Plack::Middleware::DW::CacheControl):
# dynamic responses are private unless the handler set its own policy, and
# static files are left alone.
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

use Test::More;
use HTTP::Request::Common;
use Plack::Test;

BEGIN {
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";

    eval "use Plack::Test; 1" or do {
        plan skip_all => "Plack::Test required for cache-control tests";
    };
}

plan tests => 13;

my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

my $handler_cache_control;
my $handler_status;
my $mock_ip_banned;
my $mock_bounce_url;
my $mock_rate_limited;

# A rate limit whose check always reports the limit as exceeded.
package MockExceededLimit {
    sub check { return { exceeded => 1, time_remaining => 30 } }
}

{
    no warnings 'redefine', 'once';

    # Stand-in for the routed handler: optionally sets its own Cache-Control
    # or status, the way journal pages, no_cache routes and userpics do.
    *DW::Routing::call = sub {
        my $r = DW::Request->get;
        $r->header_out( 'Cache-Control' => $handler_cache_control )
            if defined $handler_cache_control;
        $r->status( $handler_status // 200 );
        $r->print('OK') unless $handler_status;
        return 0;
    };

    *LJ::Session::session_from_cookies = sub {
        my ( $class, %opts ) = @_;
        ${ $opts{redirect_ref} } = $mock_bounce_url if $opts{redirect_ref};
        return undef;
    };
    *LJ::sysban_check                    = sub { return $_[0] eq 'ip' && $mock_ip_banned };
    *LJ::Sysban::tempban_check           = sub { return 0 };
    *LJ::UniqCookie::ensure_cookie_value = sub { return };
    *LJ::UniqCookie::parts_from_cookie   = sub { return };
    *DW::RateLimit::ip_is_excluded       = sub { return 0 };
    *DW::RateLimit::get = sub {
        return $mock_rate_limited ? bless( {}, 'MockExceededLimit' ) : undef;
    };
}

sub reset_mocks {
    $handler_cache_control = undef;
    $handler_status        = undef;
    $mock_ip_banned        = 0;
    $mock_bounce_url       = undef;
    $mock_rate_limited     = 0;
}

sub fetch {
    my ($path) = @_;
    my $res;
    test_psgi $app, sub { $res = $_[0]->( GET $path ) };
    return $res;
}

reset_mocks();
{
    my $res = fetch('/');
    is( $res->code, 200, 'dynamic page served' );
    is( $res->header('Cache-Control'), 'private, no-cache', 'dynamic page is private' );
}

reset_mocks();
$handler_cache_control = 'public, max-age=86400, s-maxage=31536000, no-transform';
{
    my $res = fetch('/');
    is( $res->header('Cache-Control'),
        $handler_cache_control, "handler's own Cache-Control is kept, not replaced" );
}

# A 304 from a handler with no policy of its own gets the same default as
# its 200 would.
reset_mocks();
$handler_status = 304;
{
    my $res = fetch('/');
    is( $res->code, 304, 'handler returned 304' );
    is( $res->header('Cache-Control'), 'private, no-cache', 'headerless 304 is private' );
}

reset_mocks();
$mock_ip_banned = 1;
{
    my $res = fetch('/');
    is( $res->code, 403, 'sysbanned request is refused' );
    is( $res->header('Cache-Control'), 'private, no-cache', 'sysban 403 is private' );
}

reset_mocks();
$mock_rate_limited = 1;
{
    my $res = fetch('/');
    is( $res->code, 429, 'rate-limited request is refused' );
    is( $res->header('Cache-Control'), 'private, no-cache', 'rate limit 429 is private' );
}

reset_mocks();
$mock_bounce_url = 'http://www.example.com/misc/get_domain_session';
{
    my $res = fetch('/');
    is( $res->code, 303, 'Auth bounces to the domain-session page' );
    is( $res->header('Cache-Control'), 'private, no-cache', 'Auth bounce is private' );
}

reset_mocks();
{
    my $res = fetch('/stc/lj_base.css');
    ok( $res->code == 200 && !defined $res->header('Cache-Control'),
        'static file gets no Cache-Control' );

    $res = fetch('/stc/css/skins/??celerity.css,lynx.css');
    ok(
        $res->code == 200 && !defined $res->header('Cache-Control'),
        'concatenated static resource gets no Cache-Control'
    );
}
