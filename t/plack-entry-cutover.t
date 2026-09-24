#!/usr/bin/perl
# Characterize the T2 entry cutover: /update and /editjournal?itemid= are
# fully graduated to the native entry form. GET always redirects; a stale
# POST is shown its exact submitted subject/body for manual copying and
# never saved (see t/plack-entry-recovery.t for that page's own coverage).
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;

use Test::More;
use File::Find;
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

subtest 'the updatepage beta no longer gates anything reachable' => sub {

    # The graduation removed the beta check entirely rather than leaving it
    # in place for a still-unreferenced code path: assert it directly in the
    # two files the plan names as the removal targets, and confirm the live
    # HTTP behavior is unconditional (a plain, never-opted-in account gets
    # the exact same redirect/carry-over the old code reserved for the beta).
    my $poll_source = do {
        local $/;
        open my $fh, '<', "$ENV{LJHOME}/cgi-bin/DW/Controller/Poll.pm" or die $!;
        <$fh>;
    };
    unlike(
        $poll_source,
        qr/user_in_beta\(\s*\$remote\s*=>\s*["']updatepage["']\s*\)/,
        'Poll.pm no longer branches on the updatepage beta'
    );

    my $form_source = do {
        local $/;
        open my $fh, '<', "$ENV{LJHOME}/views/entry/form.tt" or die $!;
        <$fh>;
    };
    unlike( $form_source, qr/betacommunity/, 'the entry form no longer renders the beta banner' );

    ok(
        !LJ::BetaFeatures->user_in_beta( $owner => 'updatepage' ),
        'fixture confirms the account was never opted into the beta'
    );

    test_psgi $app, sub {
        my $send = shift;
        my $req  = GET '/update';
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is( $res->code, 302, 'a never-opted-in account still gets the unconditional redirect' );
        is( URI->new( $res->header('Location') )->path,
            '/entry/new',
            'a never-opted-in account redirects to the native path exactly as any account would' );
    };
};

subtest 'F2: .bml suffixes still resolve natively after the retired pages are deleted' => sub {
    ok( !-e "$ENV{LJHOME}/htdocs/update.bml", 'htdocs/update.bml no longer exists on disk' );
    ok(
        !-e "$ENV{LJHOME}/htdocs/editjournal.bml",
        'htdocs/editjournal.bml no longer exists on disk'
    );
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

subtest 'F2: pages with no native route are gone' => sub {
    test_psgi $app, sub {
        my $send = shift;
        for my $path (
            qw(/imgupload /imgupload.bml /tools/endpoints/draft /tools/endpoints/draft.bml))
        {
            my $res = $send->( GET $path );
            is( $res->code, 404, "$path is gone (no native route, retired BML file deleted)" );
        }
    };
};

subtest 'native success links point at the native edit URL' => sub {
    my $entry = $owner->t_post_fake_entry(
        subject => 'Success link subject',
        body    => 'Success link body',
    );
    test_psgi $app, sub {
        my $send = shift;
        my $req  = GET '/entry/' . $owner->user . '/' . $entry->ditemid . '/edit';
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is( $res->code, 200, 'owner can load the native edit form to check its post-save wiring' );
        unlike( $res->content, qr{/editjournal\?itemid=},
            'the native edit form carries no old-style editjournal itemid link' );
    };
};

subtest 'F2: no surviving file references the deleted legacy pages or their JS' => sub {
    my @offenders;
    my @deleted_files = (
        qr{\bjs/entry\.js\b},            qr{\bjs/xpost\.js\b},
        qr{\bhtdocs/imgupload\.bml\b},   qr{\bhtdocs/update\.bml\b},
        qr{\bhtdocs/editjournal\.bml\b}, qr{\btools/endpoints/draft\.bml\b},
        qr{\bUserpicSelector\b},
    );
    File::Find::find(
        {
            wanted => sub {
                return unless -f $_ && /\.(?:tt|pm|js|bml)$/;
                return if $File::Find::name =~ m{/t/plack-entry-cutover\.t$};
                open my $fh, '<', $_ or return;
                local $/;
                my $content = <$fh>;
                for my $pattern (@deleted_files) {
                    push @offenders, "$File::Find::name: $pattern" if $content =~ $pattern;
                }
            },
            no_chdir => 1,
        },
        "$ENV{LJHOME}/cgi-bin",
        "$ENV{LJHOME}/views",
        "$ENV{LJHOME}/htdocs",
    );
    is_deeply( \@offenders, [],
        'no surviving file references a deleted F2 page, script, or widget' );
};

done_testing;
