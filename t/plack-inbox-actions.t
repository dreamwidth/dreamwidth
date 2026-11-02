#!/usr/bin/perl
#
# t/plack-inbox-actions.t
#
# Code-injection regression for the inbox action RPC
# (/__rpc_inbox_actions, DW::Controller::Inbox::action_handler).
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

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::JSON qw(from_json to_json);
use LJ::Session;
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub form_token {
    my ($content) = @_;
    return $1 if $content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
    return;
}

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'inboxActions';

my $u = temp_user();
$u->update_self( { status => 'A' } );
my $session = LJ::Session->create( $u, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;

test_psgi $app, sub {
    my $send  = shift;
    my $cb    = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };
    my $token = form_token( $cb->( GET '/inbox' )->content );
    ok( $token, 'inbox index supplies a CSRF token' );

    # The view name selects an inbox method; it must never reach string eval.
    $main::INBOX_VIEW_INJECTION_CANARY = 0;
    my $res = $cb->(
        POST '/__rpc_inbox_actions',
        'Content-Type' => 'application/json',
        Content        => to_json(
            {
                action       => 'delete_all',
                view         => 'items; $main::INBOX_VIEW_INJECTION_CANARY = 1; #',
                page         => 1,
                itemid       => 0,
                lj_form_auth => $token,
            }
        ),
    );
    ok( from_json( $res->content )->{success}, 'the crafted request reaches the action handler' );
    is( $main::INBOX_VIEW_INJECTION_CANARY, 0, 'a crafted view name cannot execute code' );
};

done_testing;
