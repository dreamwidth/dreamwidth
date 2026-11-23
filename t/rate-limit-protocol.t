# t/rate-limit-protocol.t
#
# Test that XML-RPC and flat protocol requests are rate limited per user once
# they authenticate, and per IP otherwise.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw( temp_user );
use DW::RateLimit;
use HTTP::Request::Common;
use Plack::Test;

my $u = temp_user();
$u->set_password('right-password');
my $other = temp_user();
$other->set_password('other-password');
my $stranger = temp_user();    # only ever fails to log in

my $app  = do "$ENV{LJHOME}/app.psgi" or die $@;
my $test = Plack::Test->create($app);

# The first request (re)loads site config, so override it afterwards. Plack::Test
# requests come from 127.0.0.1, which is normally exempt.
$test->request( GET 'http://www.dw.test/' );
local $LJ::RATE_LIMIT_EXCLUDE_IP = sub { 0 };
my $IP = '127.0.0.1';

local $LJ::RATE_LIMITS{anonymous_requests}     = { rate => '3/60s' };
local $LJ::RATE_LIMITS{authenticated_requests} = { rate => '5/60s' };
local $LJ::RATE_LIMITS{protocol_challenges}    = { rate => '4/60s' };
local $LJ::RATE_LIMITS{protocol_requests}      = { rate => '1000/60s' };

my $reset = sub {
    DW::RateLimit->get( $_, rate => '1/60s' )->reset( ip => $IP )
        foreach qw( anonymous_requests protocol_challenges protocol_requests );
    DW::RateLimit->get( 'authenticated_requests', rate => '1/60s' )->reset( userid => $_->userid )
        foreach $u, $other;
};

my $flat = sub {
    my (%args) = @_;
    return $test->request( POST 'http://www.dw.test/interface/flat', [ ver => 1, %args ] );
};
my $login = sub {
    my ( $user, $password ) = @_;
    return $flat->( mode => 'login', user => $user->user, password => $password );
};
my $xmlrpc = sub {
    my ( $method, %args ) = @_;
    my $members = join '',
        map { "<member><name>$_</name><value><string>$args{$_}</string></value></member>" }
        sort keys %args;
    return $test->request(
        POST 'http://www.dw.test/interface/xmlrpc',
        Content_Type => 'text/xml',
        Content      => '<?xml version="1.0"?><methodCall>'
            . "<methodName>LJ.XMLRPC.$method</methodName><params><param><value><struct>"
            . $members
            . '</struct></value></param></params></methodCall>'
    );
};
my $flat_ok = sub { $_[0]->code == 200 && $_[0]->content =~ /^success\nOK$/m };

# Rate limit state lives in memcache, which the test config doesn't have.
LJ::Test::with_fake_memcache {
    subtest 'authenticated calls use the per-user limit, not the per-IP one' => sub {
        $reset->();

        # Use up the IP's anonymous allowance with calls that never authenticate.
        for my $i ( 1 .. 3 ) {
            is( $flat->( mode => 'login' )->code, 200, "unauthenticated call $i allowed" );
        }
        is( $flat->( mode => 'login' )->code, 429, 'next unauthenticated call is blocked' );

        # Authenticated calls from the same IP are unaffected, up to the user's limit.
        for my $i ( 1 .. 5 ) {
            ok( $flat_ok->( $login->( $u, 'right-password' ) ), "authenticated call $i allowed" );
        }
        my $res = $login->( $u, 'right-password' );
        is( $res->code, 429, 'call over the user limit is blocked' );
        ok( $res->header('Retry-After'), 'with Retry-After' );

        # Each user has their own bucket.
        ok( $flat_ok->( $login->( $other, 'other-password' ) ),
            'another user on the IP is allowed' );
    };

    subtest 'failed logins count against the per-IP limit' => sub {
        $reset->();
        my $res = $login->( $stranger, 'wrong' );
        is( $res->code, 200, 'failed login answered normally' );
        like( $res->content, qr/errmsg\nInvalid password/, 'with the usual error' );
        for my $i ( 2 .. 3 ) {
            is( $login->( $stranger, 'wrong' )->code, 200, "failed login $i allowed" );
        }
        is( $login->( $stranger, 'wrong' )->code, 429, 'next failed login is blocked' );
        ok( $flat_ok->( $login->( $u, 'right-password' ) ), 'a real login still works' );
    };

    subtest 'getchallenge has its own per-IP limit' => sub {
        $reset->();
        for my $i ( 1 .. 4 ) {
            like( $flat->( mode => 'getchallenge' )->content,
                qr/challenge\nc0:/, "challenge $i issued" );
        }
        is( $flat->( mode => 'getchallenge' )->code, 429, 'next challenge is blocked' );
        is( $flat->( mode => 'login' )->code,        200, 'anonymous allowance is untouched' );
    };

    subtest 'XML-RPC is limited the same way' => sub {
        $reset->();
        my $res = $xmlrpc->('getchallenge');
        is( $res->code, 200, 'getchallenge allowed' );
        like( $res->content, qr/<name>challenge<\/name>/, 'returns a challenge' );

        for my $i ( 1 .. 5 ) {
            $res = $xmlrpc->( 'login', username => $u->user, password => 'right-password' );
            ok( $res->code == 200 && $res->content !~ /<fault>/, "login $i allowed" );
        }
        $res = $xmlrpc->( 'login', username => $u->user, password => 'right-password' );
        is( $res->code, 429, 'call over the user limit is a 429, not a fault' );
        ok( $res->header('Retry-After'), 'with Retry-After' );

        for my $i ( 1 .. 3 ) {
            $res = $xmlrpc->( 'login', username => $stranger->user, password => 'wrong' );
            like( $res->content, qr/<fault>/, "failed login $i is a fault" );
        }
        is( $xmlrpc->( 'login', username => $stranger->user, password => 'wrong' )->code,
            429, 'next failed login is a 429' );
    };

    subtest 'the per-IP backstop applies before anything else' => sub {
        $reset->();
        local $LJ::RATE_LIMITS{protocol_requests} = { rate => '2/60s' };
        for my $i ( 1 .. 2 ) {
            ok( $flat_ok->( $login->( $u, 'right-password' ) ), "call $i allowed" );
        }
        is( $login->( $u, 'right-password' )->code, 429, 'third call blocked by the backstop' );
    };

    subtest 'other pages are still limited per IP when anonymous' => sub {
        $reset->();
        $test->request( GET 'http://www.dw.test/' ) for 1 .. 3;
        is( $test->request( GET 'http://www.dw.test/' )->code, 429, 'anonymous page view blocked' );
    };
};

done_testing();
