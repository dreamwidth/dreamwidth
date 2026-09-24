#!/usr/bin/perl
# Native redirect contract for tools OPML.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $u = temp_user();
$u->update_self( { status => 'A' } );
my $s = LJ::Session->create( $u, nolog => 1 );
my $cookie =
    'ljmastersession=' . $s->master_cookie_string . '; ljloggedin=' . $s->loggedin_cookie_string;
test_psgi $app, sub {
    my $send   = shift;
    my $logged = GET '/tools/opml';
    $logged->header( Cookie => $cookie );
    my $r = $send->($logged);
    is( $r->code, 303, 'logged-in no-user OPML uses the native 303 redirect' );
    is(
        $r->header('Location'),
        "/tools/opml?user=" . $u->user,
        'native OPML redirect retains the legacy intended destination'
    );
    my $explicit = GET '/tools/opml?user=' . $u->user;
    $explicit->header( Cookie => $cookie );
    $r = $send->($explicit);
    is( $r->code, 200, 'explicit user OPML remains output rather than redirect' );
    like( $r->content, qr/<opml\b/i, 'explicit user retains OPML document output' );
    $LJ::CACHED_REMOTE = 0;
    $LJ::CACHE_REMOTE  = undef;
    $r                 = $send->( GET '/tools/opml' );
    is( $r->code, 302, 'anonymous no-user OPML retains its authentication redirect' );
    like( $r->header('Location'),
        qr{/login}, 'anonymous no-user redirect destination remains the login flow' );
};
done_testing;
