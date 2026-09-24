#!/usr/bin/perl
#
# t/plack-entry-cutover.t
#
# Characterize the T2 entry cutover: /update and /editjournal?itemid= are
# fully graduated to the native entry form. GET always redirects; a stale
# POST is shown its exact submitted subject/body for manual copying and
# never saved (see t/plack-entry-recovery.t for that page's own coverage).
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

sub cookie_for {
    my ($u) = @_;
    my $session = LJ::Session->create( $u, nolog => 1 );
    return
          'ljmastersession='
        . $session->master_cookie_string
        . '; ljloggedin='
        . $session->loggedin_cookie_string;
}

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $owner_cookie = cookie_for($owner);
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryCutover';

test_psgi $app, sub {
    my $send     = shift;
    my $as_owner = sub {
        my ($req) = @_;
        $req->header( Cookie => $owner_cookie );
        return $send->($req);
    };

    subtest 'GET redirects to the native form with mapped arguments' => sub {
        for my $path (qw(/update /update.bml)) {
            my $res =
                $as_owner->( GET $path
                    . '?subject=Cutover+subject&event=Cutover+event&prop_taglist=one%2C+two&share=http%3A%2F%2Fexample.com%2F&altlogin=1'
                );
            is( $res->code, 302, "$path GET redirects" );
            my $location = URI->new( $res->header('Location') );
            is( $location->path, '/entry/new', "$path redirects to the native new-entry path" );
            my %query = $location->query_form;
            is( $query{subject}, 'Cutover subject',     "$path maps subject" );
            is( $query{event},   'Cutover event',       "$path maps event" );
            is( $query{tags},    'one, two',            "$path maps prop_taglist to tags" );
            is( $query{share},   'http://example.com/', "$path maps share" );
            ok( !exists $query{altlogin}, "$path drops altlogin" );
        }

        my $res      = $as_owner->( GET '/update?usejournal=' . $owner->user );
        my $location = URI->new( $res->header('Location') );
        is(
            $location->path,
            '/entry/' . $owner->user . '/new',
            'a named usejournal redirects to that journal\'s native new-entry path'
        );
    };

    subtest 'a hostile usejournal never reaches the redirect Location unsanitized' => sub {
        for my $hostile ( '//evil.example/x', '..%2F..' ) {
            my $res = $as_owner->( GET '/update?subject=Hostile+subject&usejournal=' . $hostile );
            is( $res->code, 302, "usejournal=$hostile GET still redirects" );
            my $location = URI->new( $res->header('Location') );
            is( $location->path, '/entry/new', "usejournal=$hostile falls back to /entry/new" );
            my %query = $location->query_form;
            is(
                $query{subject},
                'Hostile subject',
                "usejournal=$hostile still maps other query args"
            );
        }
    };

    subtest 'edit GET redirects to the native edit form' => sub {
        my $entry = $owner->t_post_fake_entry(
            subject => 'Edit cutover subject',
            body    => 'Edit cutover body',
        );
        for my $path ( '/editjournal', '/editjournal.bml' ) {
            my $res = $as_owner->( GET $path . '?itemid=' . $entry->ditemid );
            is( $res->code, 302, "$path?itemid GET redirects" );
            is(
                URI->new( $res->header('Location') )->path,
                '/entry/' . $owner->user . '/' . $entry->ditemid . '/edit',
                "$path?itemid redirects to the native edit path"
            );
        }
    };

    subtest 'a hostile journal/usejournal never reaches the edit redirect Location unsanitized' =>
        sub {
        my $entry = $owner->t_post_fake_entry(
            subject => 'Hostile edit redirect subject',
            body    => 'Hostile edit redirect body',
        );
        for my $hostile ( '//evil.example/x', '..%2F..' ) {
            for my $param (qw(usejournal journal)) {
                my $res =
                    $as_owner->(
                    GET '/editjournal?itemid=' . $entry->ditemid . "&$param=" . $hostile );
                is( $res->code, 302, "$param=$hostile edit GET still redirects" );
                is(
                    URI->new( $res->header('Location') )->path,
                    '/entry/new',
                    "$param=$hostile falls back to /entry/new, never an unsanitized path"
                );
            }
        }
        };

};

subtest 'F2: .bml suffixes still resolve natively after the retired pages are deleted' => sub {
    my $entry = $owner->t_post_fake_entry(
        subject => 'F2 routing-precedence subject',
        body    => 'F2 routing-precedence body',
    );
    test_psgi $app, sub {
        my $send = shift;
        for my $path ( '/update.bml', '/editjournal.bml?itemid=' . $entry->ditemid ) {
            my $req = GET $path;
            $req->header( Cookie => $owner_cookie );
            my $res = $send->($req);
            is( $res->code, 302,
                "$path still resolves through DW::Routing, not the deleted BML file" );
        }
    };
};

done_testing;
