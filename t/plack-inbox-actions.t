#!/usr/bin/perl
#
# t/plack-inbox-actions.t
#
# Security and CSRF regressions for the native inbox action RPCs:
# /__rpc_inbox_actions (DW::Controller::Inbox::action_handler) and
# /__rpc_esn_inbox (DW::Controller::RPC::MiscLegacy::esn_inbox_handler).
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

use LJ::Event::AddedToCircle;
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

my $u  = temp_user();
my $u2 = temp_user();
$_->update_self( { status => 'A' } ) for $u, $u2;
my $session = LJ::Session->create( $u, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;

# Seed one real inbox item so action/view handling has something to act on.
# enqueue() returns an LJ::NotificationItem object, not a bare qid.
my $evt       = LJ::Event::AddedToCircle->new( $u2, $u, 2 );
my $inbox     = $u->notification_inbox;
my $seed_item = $inbox->enqueue( event => $evt );
my $qid       = $seed_item->qid;
ok( $qid, 'seeded a real inbox item for these tests' );

test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };

    my $index = $cb->( GET '/inbox' );
    is( $index->code, 200, 'inbox index renders' );
    my $token = form_token( $index->content );
    ok( $token, 'inbox index supplies a CSRF token' );

    # --- Item 1: action_handler validates view before any method dispatch,
    # and items_by_view no longer stringifies it into eval. ---

    # This is a syntactically valid injection under the removed
    # `eval "\$inbox->${view}_items"`: it would call a real method, then
    # execute arbitrary code, then comment out the appended "_items" text.
    # Under the fix it must never even reach that method-name lookup.
    $main::INBOX_VIEW_INJECTION_CANARY = 0;
    my $malicious_view = 'items; $main::INBOX_VIEW_INJECTION_CANARY = 1; #';

    my $res = $cb->(
        POST '/__rpc_inbox_actions',
        'Content-Type' => 'application/json',
        Content        => to_json(
            {
                action       => 'delete_all',
                view         => $malicious_view,
                page         => 1,
                itemid       => 0,
                lj_form_auth => $token,
            }
        ),
    );
    is( $res->code, 200, 'malicious view payload still returns HTTP 200' );
    is( $main::INBOX_VIEW_INJECTION_CANARY,
        0, 'malicious view payload never reaches string eval or executes injected code' );
    my $data = from_json( $res->content );
    ok( $data->{success}, 'malicious view payload safely falls back rather than erroring' );

    # A bogus view built only of word characters exercises the separate
    # LJ::NotificationInbox->can(...) gate, not the \W gate.
    $res = $cb->(
        POST '/__rpc_inbox_actions',
        'Content-Type' => 'application/json',
        Content        => to_json(
            {
                action       => 'delete_all',
                view         => 'nonexistentview',
                page         => 1,
                itemid       => 0,
                lj_form_auth => $token,
            }
        ),
    );
    is( $res->code, 200, 'bogus word-only view still returns HTTP 200' );
    $data = from_json( $res->content );
    ok( $data->{success}, 'bogus word-only view safely falls back rather than erroring' );

    # A real view still works after the fix.
    $res = $cb->(
        POST '/__rpc_inbox_actions',
        'Content-Type' => 'application/json',
        Content        => to_json(
            { action => 'expand', ids => $qid, view => 'circle', lj_form_auth => $token }
        ),
    );
    is( $res->code, 200, 'a real view continues to work after the fix' );
    $data = from_json( $res->content );
    ok( $data->{success}, 'a real view request still succeeds' );

    # --- W3: /__rpc_esn_inbox no longer has any mutating mode at all (they
    # were esn_inbox.js's, and esn_inbox.js is deleted with the legacy inbox
    # pages it belonged to). Only the unauthenticated nav-count poll remains;
    # every other action name -- including the old mutating ones -- is
    # rejected regardless of whether a valid token is supplied. ---

    my $esn_res = $cb->( POST '/__rpc_esn_inbox', Content => [ action => 'get_unread_items' ], );
    is( $esn_res->code, 200, 'get_unread_items returns HTTP 200 with no token' );
    my $esn_data = from_json( $esn_res->content );
    ok( !$esn_data->{error},              'get_unread_items succeeds unauthenticated' );
    ok( exists $esn_data->{unread_count}, 'get_unread_items reports an unread count' );

    for my $case (
        [ 'mark_all_read',           undef ],
        [ 'mark_all_read',           $token ],
        [ 'toggle_bookmark',         $token ],
        [ 'set_default_expand_prop', $token ],
        )
    {
        my ( $removed_action, $maybe_token ) = @$case;
        my @payload = ( action => $removed_action, cur_folder => 'all' );
        push @payload, lj_form_auth => $maybe_token if defined $maybe_token;
        my $res = $cb->( POST '/__rpc_esn_inbox', Content => \@payload );
        is( $res->code, 200, "removed action $removed_action still returns HTTP 200" );
        my $data = from_json( $res->content );
        ok( $data->{error}, "removed action $removed_action is rejected regardless of a token" );
    }
};

done_testing;
