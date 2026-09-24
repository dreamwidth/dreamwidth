#!/usr/bin/perl
# Locks two /manage/ string fixes: views/manage/index.tt's
# '.communities.invites.about ' call had a trailing space in the key
# literal, resolving to a nonexistent key instead of the real
# .communities.invites.about definition; its '.friends.groups.about' call
# named a key nothing had defined since the BML->TT conversion renamed the
# definition to .circle.groups.about without updating this call site (that
# key was, in turn, left with no caller). Copyright (c) 2026 by Dreamwidth
# Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

plan skip_all => '/manage/ string check requires a development server'
    unless $LJ::IS_DEV_SERVER;

use LJ::Session;
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $u = temp_user();
$u->update_self( { status => 'A' } );
my $session = LJ::Session->create( $u, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;

test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };

    my $res = $cb->( GET '/manage/' );
    is( $res->code, 200, '/manage/ renders' );
    like(
        $res->content,
        qr/View any pending invitations you've received to join communities\./,
'.communities.invites.about renders now that the trailing space is gone from the key literal'
    );
    like(
        $res->content,
        qr/Create, edit, or delete subgroups of your access list/,
        '.circle.groups.about renders now that the call site names its real definition'
    );
    unlike(
        $res->content,
qr/\[missing string [^\]]*(?:communities\.invites\.about|friends\.groups\.about|circle\.groups\.about)/,
        'neither key shows a missing-string banner'
    );
};

done_testing;
