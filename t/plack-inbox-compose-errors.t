#!/usr/bin/perl
#
# t/plack-inbox-compose-errors.t
#
# Authenticated compose rejection regressions; delivery is always replaced locally.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
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
use HTTP::Request::Common;
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $sender    = temp_user();
my $recipient = temp_user();
$sender->update_self(    { status => 'A' } );
$recipient->update_self( { status => 'A' } );
my $session = LJ::Session->create( $sender, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;

sub form_token {
    my ($content) = @_;
    return $1 if $content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
    return;
}

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'inboxComposeErrors';
test_psgi $app, sub {
    my $send  = shift;
    my $cb    = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };
    my $token = form_token( $cb->( GET '/inbox/compose' )->content );
    ok( $token, 'rendered compose form supplies CSRF token' );

    $recipient->set_prop( 'opt_usermsg', 'N' );
    no warnings 'redefine';
    local *LJ::Message::send = sub { die 'delivery must not run for a refusing recipient' };
    my $res = $cb->(
        POST '/inbox/compose',
        Content => [
            mode         => 'send',
            msg_to       => $recipient->user,
            msg_subject  => 'Subject retained marker',
            msg_body     => 'Body retained marker',
            lj_form_auth => $token,
        ]
    );
    like( $res->content, qr/chosen not to receive messages/i, 'recipient denial is explained' );
    like( $res->content, qr/Subject retained marker/,         'recipient denial retains subject' );
    like( $res->content, qr/Body retained marker/,            'recipient denial retains body' );
};

test_psgi $app, sub {
    my $send        = shift;
    my $unvalidated = temp_user();
    $unvalidated->update_self( { status => 'N' } );
    my $u_session = LJ::Session->create( $unvalidated, nolog => 1 );
    my $u_cookie =
          'ljmastersession='
        . $u_session->master_cookie_string
        . '; ljloggedin='
        . $u_session->loggedin_cookie_string;
    my $u_cb = sub { my $req = shift; $req->header( Cookie => $u_cookie ); return $send->($req); };

    # The inbox index has no validation gate, so it supplies a real token.
    my $u_token = form_token( $u_cb->( GET '/inbox' )->content );
    ok( $u_token, 'unvalidated sender can obtain a CSRF token' );

    my $called = 0;
    no warnings 'redefine';
    local *LJ::Message::send =
        sub { $called++; die 'delivery must not run for an unvalidated sender' };
    my $post = $u_cb->(
        POST '/inbox/compose',
        Content => [
            mode         => 'send',
            msg_to       => $recipient->user,
            msg_subject  => 'Should never send',
            msg_body     => 'Should never send',
            lj_form_auth => $u_token,
        ]
    );
    is( $post->code, 303, 'unvalidated sender is redirected before composing' );
    is( $called,     0,   'unvalidated sender cannot send a message' );
};

done_testing;
