#!/usr/bin/perl
# t/plack-shop-session.t
#
# Test the shop's domain-session round trip without exposing its internal route.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
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
use CGI::Cookie;
use HTTP::Request::Common;
use Plack::Test;
use URI;

BEGIN {
    $LJ::_T_CONFIG = 1;
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

use DW::Controller::Misc;
use LJ::Session;
use LJ::Test qw(temp_user);

# Prime the real config-modtime cache before process-local production/domain
# overrides. A first periodic reload would otherwise restore the test config.
{
    local $LJ::CACHE_CONFIG_MODTIME_LASTCHECK = 0;
    LJ::Config->start_request_reload;
}

# Select the production auth path before app.psgi decides whether to add Dev middleware.
local $ENV{LJ_IS_DEV_SERVER} = 0;
local $LJ::IS_DEV_SERVER = 0;
my $app = do "$ENV{LJHOME}/app.psgi";
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless ref $app eq 'CODE';
ok( !$LJ::IS_DEV_SERVER, 'loaded app with production authentication configuration' );

# Keep real authentication, cookie signing/validation and the helper controller.
# Only replace final page rendering and unrelated middleware checks.
{
    no warnings 'redefine', 'once';
    *DW::Routing::call = sub {
        my ( $class, %args ) = @_;
        return DW::Controller::Misc::domain_session_handler()
            if $args{uri} eq '/misc/get_domain_session';

        my $r = DW::Request->get;
        my $u = LJ::get_remote();
        $r->status(200);
        $r->content_type('text/plain');
        $r->print( $args{uri} . ':' . ( $u ? $u->id : 'anonymous' ) );
        return 0;
    };
    *LJ::sysban_check                    = sub { return 0 };
    *LJ::Sysban::tempban_check           = sub { return 0 };
    *LJ::UniqCookie::parts_from_cookie   = sub { return () };
    *LJ::UniqCookie::ensure_cookie_value = sub { return };
    *DW::RateLimit::get                  = sub { return undef };
}

local $LJ::USER_DOMAIN        = 'example.org';
local $LJ::DOMAIN_WEB         = 'www.example.org';
local $LJ::DOMAIN             = 'example.org';
local $LJ::SITEROOT           = 'https://www.example.org';
local $LJ::PROTOCOL           = 'https';
local $LJ::DOMSESS_EXPIRATION = 0;
local %LJ::SUBDOMAIN_FUNCTION = ();

my $u = temp_user();
$u->update_self( { status => 'A', statusvis => 'V' } );
my $sess = LJ::Session->create( $u, exptype => 'once', nolog => 1 );
ok( $sess, 'created a synthetic session' ) or BAIL_OUT('session creation failed');
my $loggedin = $sess->loggedin_cookie_string;
my $master   = $sess->master_cookie_string;
my $domain   = $sess->domsess_cookie_string('ljdomsess.shop');
my $invalid  = $domain;
$invalid =~ s/:g([0-9a-f])/':g' . ( $1 eq '0' ? '1' : '0' )/e;

sub cookie_header {
    my (%cookies) = @_;
    return join '; ', map {
        my $cookie = CGI::Cookie->new( -name => $_, -value => $cookies{$_} )->as_string;
        ( split /;/, $cookie )[0];
    } sort keys %cookies;
}

sub query_args {
    return { URI->new( $_[0] )->query_form };
}

sub domain_cookies {
    my ($res) = @_;
    return grep { /^ljdomsess\./ } $res->header('Set-Cookie');
}

sub policy_checked_client {
    my ($client) = @_;
    return sub {
        my $res = $client->(@_);
        is( 0 + $LJ::IS_DEV_SERVER, 0, 'request retains production authentication policy' );
        is( $LJ::SITEROOT, 'https://www.example.org', 'request retains synthetic domain config' );
        return $res;
    };
}

for my $initial ( 'missing', 'invalid' ) {
    for my $path ( '/', '/randomgift?type=paid&note=A%2FB', '/cart/' ) {
        subtest "$initial domain cookie: $path" => sub {
            test_psgi $app, sub {
                my $cb  = policy_checked_client(shift);
                my %jar = ( ljloggedin => $loggedin );
                $jar{'ljdomsess.shop'} = $invalid if $initial eq 'invalid';
                my $url = "https://shop.example.org$path";
                my $res = $cb->( GET $url, Cookie => cookie_header(%jar) );
                is( $res->code, 303, 'missing or invalid cookie starts a bounce' );

                my $bounce = URI->new( $res->header('Location') );
                is( $bounce->host, 'www.example.org',          'bounce goes to the master host' );
                is( $bounce->path, '/misc/get_domain_session', 'bounce uses the helper' );
                my $return = query_args($bounce)->{return};
                is(
                    URI->new($return)->path,
                    URI->new($url)->path,
                    'return path is the browser path, without the internal /shop prefix'
                );
                is_deeply( query_args($return), query_args($url), 'return query survives' );

                # Master credentials belong only on the master-host leg.
                $res = $cb->(
                    GET $bounce,
                    Cookie => cookie_header( ljloggedin => $loggedin, ljmastersession => $master )
                );
                is( $res->code, 303, 'master helper issues a signed domain-session URL' );
                my $setter = URI->new( $res->header('Location') );
                is( $setter->host, 'shop.example.org', 'setter stays on the shop host' );
                is( $setter->path, '/__setdomsess',    'setter bypasses shop rewriting' );
                is( query_args($setter)->{dest}, $return, 'setter preserves the return URL' );

                $res = $cb->( GET $setter, Cookie => cookie_header(%jar) );
                is( $res->code,               303,     'setter redirects back to the shop' );
                is( $res->header('Location'), $return, 'setter returns to the external URL' );
                my @cookies = domain_cookies($res);
                is( scalar @cookies, 1, 'setter emits one domain cookie' );
                ok( scalar( ( $cookies[0] // '' ) =~ /;\s*path=\/(?:;|$)/i ),
                    'shop cookie covers root' );
                ok( scalar( ( $cookies[0] // '' ) =~ /;\s*httponly(?:;|$)/i ),
                    'cookie remains HttpOnly' );
                my %set = CGI::Cookie->parse( $cookies[0] // '' );
                $jar{'ljdomsess.shop'} = $set{'ljdomsess.shop'}->value
                    if $set{'ljdomsess.shop'};

                $res = $cb->( GET $return, Cookie => cookie_header(%jar) );
                is( $res->code, 200, 'round trip terminates without another bounce' );
                my $route = URI->new($url)->path;
                $route =~ s/\/$//;
                is(
                    $res->content,
                    '/shop' . $route . ':' . $u->id,
                    'the authenticated page uses exactly one internal shop prefix'
                );
            };
        };
    }
}

test_psgi $app, sub {
    my $cb  = policy_checked_client(shift);
    my $res = $cb->( GET 'https://shop.example.org/' );
    is( $res->content, '/shop:anonymous', 'anonymous shop visits do not bounce' );

    my $cookie = cookie_header( ljloggedin => $loggedin, 'ljdomsess.shop' => $domain );
    $res = $cb->( GET 'https://shop.example.org/', Cookie => $cookie );
    is( $res->content, '/shop:' . $u->id, 'warm domain session does not bounce' );

    $res = $cb->(
        POST 'https://shop.example.org/cart',
        Cookie  => cookie_header( ljloggedin => $loggedin ),
        Content => [ fixture => 'only' ]
    );
    is( $res->code, 200, 'POST with a missing domain cookie is not redirected' );
    is( $res->content, '/shop/cart:anonymous', 'POST keeps the internal route' );

    $res = $cb->(
        GET 'https://www.example.org/shop',
        Cookie => cookie_header(
            ljloggedin      => $loggedin,
            ljmastersession => $master
        )
    );
    is( $res->content, '/shop:' . $u->id, 'master-host shop routing is unchanged' );

    # Back-to-back requests on the same app must not retain the shop path.
    $res = $cb->(
        GET 'https://someuser.example.org/profile?style=mine',
        Cookie => cookie_header( ljloggedin => $loggedin )
    );
    my $return = query_args( $res->header('Location') )->{return};
    is( URI->new($return)->path, '/profile',             'journal bounce keeps its own path' );
    is( URI->new($return)->host, 'someuser.example.org', 'journal bounce keeps its own host' );

    {
        local $LJ::SUBDOMAIN_FUNCTION{shop} = 'shop';
        $res = $cb->( GET 'https://shop.example.org/randomgift?type=paid' );
        is(
            $res->header('Location'),
            'https://www.example.org/shop/randomgift?type=paid',
            'configured shop redirect remains unchanged'
        );
    }

    for my $dest ( 'https://outside.example/', 'https://shop.example.org.evil.test/' ) {
        my $setter = URI->new('https://shop.example.org/__setdomsess');
        $setter->query_form( dest => $dest, k => 'ljdomsess.shop', v => $domain );
        $res = $cb->( GET $setter, Cookie => cookie_header( ljloggedin => $loggedin ) );
        is( $res->header('Location'), $LJ::SITEROOT, 'external destination is rejected' );
        is( scalar domain_cookies($res), 0, 'external destination cannot set a cookie' );
    }

    for my $case (
        [ 'invalid signature',         $invalid, $loggedin ],
        [ 'wrong logged-in session',   $domain,  'u0:s0' ],
        [ 'missing logged-in session', $domain,  undef ]
        )
    {
        my ( $name, $value, $li ) = @$case;
        my $dest   = 'https://shop.example.org/';
        my $setter = URI->new('https://shop.example.org/__setdomsess');
        $setter->query_form( dest => $dest, k => 'ljdomsess.shop', v => $value );
        $res = $cb->(
            GET $setter, Cookie => cookie_header( defined $li ? ( ljloggedin => $li ) : () )
        );
        is( $res->header('Location'),    $dest, "$name returns only to the validated destination" );
        is( scalar domain_cookies($res), 0,     "$name cannot set a domain cookie" );
    }
};

# temp_user's END handler removes the account; remove its session as well.
$sess->destroy;

done_testing();
