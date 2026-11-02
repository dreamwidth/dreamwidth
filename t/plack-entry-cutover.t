#!/usr/bin/perl
#
# t/plack-entry-cutover.t
#
# The old /update and /editjournal?itemid= entry URLs: GET redirects to the
# native entry form without an open redirect, and a stale old-editor tab
# can still autosave its draft.
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
use URI;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Session;
use LJ::Test qw(temp_user);

plan skip_all => 'Entry cutover integration requires a development server'
    unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $session = LJ::Session->create( $owner, nolog => 1 );
my $owner_cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryCutover';

my $hostile = '//evil.example/x';

test_psgi $app, sub {
    my $send     = shift;
    my $as_owner = sub {
        my ($req) = @_;
        $req->header( Cookie => $owner_cookie );
        return $send->($req);
    };

    subtest 'a hostile usejournal never reaches the redirect Location unsanitized' => sub {
        my $res = $as_owner->( GET '/update?subject=Hostile+subject&usejournal=' . $hostile );
        is( $res->code, 302, 'hostile usejournal GET still redirects' );
        my $location = URI->new( $res->header('Location') );
        is( $location->path, '/entry/new', 'hostile usejournal falls back to /entry/new' );
        is(
            { $location->query_form }->{subject},
            'Hostile subject',
            'hostile usejournal still maps other query args'
        );
    };

    subtest 'a hostile journal/usejournal never reaches the edit redirect Location unsanitized' =>
        sub {
        my $entry = $owner->t_post_fake_entry(
            subject => 'Hostile edit redirect subject',
            body    => 'Hostile edit redirect body',
        );
        for my $param (qw(usejournal journal)) {
            my $res =
                $as_owner->( GET '/editjournal?itemid=' . $entry->ditemid . "&$param=" . $hostile );
            is( $res->code, 302, "hostile $param edit GET still redirects" );
            is(
                URI->new( $res->header('Location') )->path,
                '/entry/new',
                "hostile $param falls back to /entry/new, never an unsanitized path"
            );
        }
        };

    subtest 'a stale old-editor tab still autosaves its draft' => sub {
        my $res =
            $as_owner->( POST '/tools/endpoints/draft', [ saveDraft => 'Unsaved stale-tab text' ] );
        is( $res->code, 200, 'the old autosave URL answers' );
        is(
            LJ::load_userid( $owner->userid, 1 )->draft_text,
            'Unsaved stale-tab text',
            'the draft text is saved'
        );
    };
};

done_testing;
