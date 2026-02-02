#!/usr/bin/perl
# t/plack-auth.t
#
# Tests for the Plack auth middleware (Plack::Middleware::DW::Auth).
# Uses mocking to simulate session cookie resolution without requiring DB.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
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
        plan skip_all => "Plack::Test required for auth tests";
    };
}

plan tests => 8;

# Load the Plack app
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Mock state
my $mock_sessobj;
my $mock_load_user;

# Minimal mock session object
package MockSession;

sub new {
    my ( $class, %opts ) = @_;
    return bless \%opts, $class;
}
sub owner     { return $_[0]->{owner} }
sub try_renew { }

package main;

# Minimal mock user object
package MockUser;

sub new {
    my ( $class, %opts ) = @_;
    return bless \%opts, $class;
}
sub user          { return $_[0]->{user} }
sub note_activity { }

package main;

{
    no warnings 'redefine';

    # Mock routing: return the remote user as seen by the app
    *DW::Routing::call = sub {
        my ( $class, %args ) = @_;
        my $r      = DW::Request->get;
        my $remote = $LJ::CACHE_REMOTE;
        $r->status(200);
        $r->header_out( 'Content-Type' => 'text/plain' );
        if ($remote) {
            $r->print( "user:" . $remote->user );
        }
        else {
            $r->print("user:anonymous");
        }
        return;
    };

    *LJ::Session::session_from_cookies = sub {
        return $mock_sessobj;
    };

    *LJ::load_user = sub {
        my ($username) = @_;
        return $mock_load_user->($username) if $mock_load_user;
        return undef;
    };

    # Disable sysban checks for auth tests
    *LJ::sysban_check                    = sub { return 0 };
    *LJ::Sysban::tempban_check           = sub { return 0 };
    *LJ::UniqCookie::parts_from_cookie   = sub { return () };
    *LJ::UniqCookie::ensure_cookie_value = sub { return };

    # Prevent LJ::get_remote() from going through Login.pm's full path
    # which requires a real LJ::User object. The Auth middleware sets
    # $CACHE_REMOTE directly; we just need get_remote to return it.
    *LJ::User::Login::get_remote = sub { return $LJ::CACHE_REMOTE };
}

# Helper to reset state
sub reset_mocks {
    $mock_sessobj         = undef;
    $mock_load_user       = undef;
    @LJ::CLEANUP_HANDLERS = ();
    $LJ::CACHED_REMOTE    = 0;
    $LJ::CACHE_REMOTE     = undef;
}

# Test 1: No session cookie -> anonymous
reset_mocks();
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    is( $res->code, 200, "No session cookie returns 200" );
};

# Test 2: No session cookie -> remote is anonymous
reset_mocks();
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    like( $res->content, qr/user:anonymous/, "No session cookie means anonymous user" );
};

# Test 3: Valid session cookie -> user is set as remote
reset_mocks();
my $mock_user = MockUser->new( user => 'testuser' );
$mock_sessobj = MockSession->new( owner => $mock_user );
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    like( $res->content, qr/user:testuser/, "Valid session sets remote to authenticated user" );
};

# Test 4: Session with no owner -> anonymous
reset_mocks();
$mock_sessobj = MockSession->new( owner => undef );
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/" );

    like( $res->content, qr/user:anonymous/, "Session with no owner means anonymous" );
};

# Test 5: Dev server ?as= parameter overrides remote
reset_mocks();
$mock_user    = MockUser->new( user => 'testuser' );
$mock_sessobj = MockSession->new( owner => $mock_user );
my $dev_user = MockUser->new( user => 'devuser' );
$mock_load_user = sub { return $_[0] eq 'devuser' ? $dev_user : undef };
local $LJ::IS_DEV_SERVER = 1;
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/?as=devuser" );

    like( $res->content, qr/user:devuser/, "Dev server ?as= overrides authenticated user" );
};

# Test 6: Dev server ?as= with invalid user -> logs out
reset_mocks();
$mock_user      = MockUser->new( user => 'testuser' );
$mock_sessobj   = MockSession->new( owner => $mock_user );
$mock_load_user = sub { return undef };
local $LJ::IS_DEV_SERVER = 1;
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/?as=nobody" );

    like( $res->content, qr/user:anonymous/, "Dev server ?as= with invalid user logs out" );
};

# Test 7: ?as= without a value doesn't change remote
reset_mocks();
$mock_user    = MockUser->new( user => 'testuser' );
$mock_sessobj = MockSession->new( owner => $mock_user );
local $LJ::IS_DEV_SERVER = 1;
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/?as=" );

    like( $res->content, qr/user:testuser/, "?as= with empty value does not change remote" );
};

# Test 8: ?as= rejects invalid username format
reset_mocks();
$mock_user      = MockUser->new( user => 'testuser' );
$mock_sessobj   = MockSession->new( owner => $mock_user );
$mock_load_user = sub { return MockUser->new( user => 'badguy' ) };
local $LJ::IS_DEV_SERVER = 1;
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "/?as=invalid!user" );

    like( $res->content, qr/user:testuser/, "?as= with invalid username format is ignored" );
};
