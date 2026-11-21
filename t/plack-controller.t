#!/usr/bin/perl
# t/plack-controller.t
#
# Tests shared controller behavior through the full Plack stack.
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
    $LJ::_T_CONFIG = 1;
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

use LJ::Test qw(temp_user);

# Load the Plack app
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Test: GET /login returns 200 with login form HTML
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "http://localhost/login?skin=global" );

    is( $res->code, 200, "GET /login returns 200" );
    like( $res->content, qr/<form/i, "Response contains a login form" );

    # /login must be marked no-cache: the form embeds a uniq-bound form_auth
    # token, so a shared cache serving one user's page to another would break
    # login with "Invalid form submission".
    like( $res->header('Cache-Control'), qr/no-cache/, "GET /login is marked no-cache" );
};

my $visible   = temp_user();
my $deleted   = temp_user();
my $suspended = temp_user();
$deleted->update_self(   { statusvis => 'D' } );
$suspended->update_self( { statusvis => 'S' } );

test_psgi $app, sub {
    my $cb   = shift;
    my $base = 'http://localhost';
    local $LJ::IS_DEV_SERVER = 1;

    is( $cb->( GET "$base/tools/search" )->code, 200, 'search still allows anonymous visitors' );
    is( $cb->( GET "$base/tools/search?as=" . $visible->user )->code,
        200, 'search allows a visible account' );
    is( $cb->( GET "$base/manage/index" )->code,
        302, 'account management still redirects anonymous visitors to login' );

    for my $account ( $deleted, $suspended ) {
        my $query  = '?as=' . $account->user;
        my $status = $account->statusvis;
        is( $cb->( GET "$base/tools/search$query" )->code,
            403, "search rejects a signed-in account with status $status" );
        is( $cb->( GET "$base/manage/index$query" )->code,
            403, "account management rejects a signed-in account with status $status" );
        for my $path ( '/accountstatus', '/logout', '/support/submit' ) {
            is( $cb->( GET "$base$path$query" )->code,
                200, "$path remains available with account status $status" );
        }
    }
};

done_testing;
