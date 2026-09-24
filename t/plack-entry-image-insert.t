#!/usr/bin/perl
# Native image insertion help hook rendering.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Session;
use LJ::Test qw(temp_user);
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq "CODE";
my $u = temp_user();
$u->update_self( { status => "A" } );
my $e = $u->t_post_fake_entry( subject => "x", body => "y", security => "private" );
my $s = LJ::Session->create( $u, nolog => 1 );
my $c =
    "ljmastersession=" . $s->master_cookie_string . "; ljloggedin=" . $s->loggedin_cookie_string;
no warnings "redefine";
local *LJ::Hooks::run_hook = sub { return q{<a href="/faq-marker">FAQ marker</a>} };
test_psgi $app, sub {
    my $cb = shift;
    for my $path ( "/entry/new", "/entry/" . $u->user . "/" . $e->ditemid . "/edit" ) {
        my $r = GET $path;
        $r->header( Cookie => $c );
        my $res = $cb->($r);
        is( $res->code, 200, "$path renders" );
        like(
            $res->content,
            qr{<a href="/faq-marker">FAQ marker</a>},
            "$path renders faqlink hook"
        );
        unlike(
            $res->content,
            qr{\.image\.(?:open|insert|cancel)},
            "$path has no missing image strings"
        );
    }
};
done_testing;
