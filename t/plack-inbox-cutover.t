#!/usr/bin/perl
#
# t/plack-inbox-cutover.t
#
# Native inbox cutover: canonical routes resolve directly, retained old
# links redirect with their query args preserved, and the inbox beta gate
# is gone everywhere except the retained (still-unreachable) .bml page.
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

use File::Find;
use HTML::Form;
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Event::AddedToCircle;
use LJ::Message;
use LJ::Session;
use LJ::Test qw(temp_user);

plan skip_all => 'Inbox cutover characterization requires a development server'
    unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub form_token {
    my ($content) = @_;
    return $1 if $content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
    return;
}

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'inboxCutover';

my $u  = temp_user();
my $u2 = temp_user();
$_->update_self( { status => 'A' } ) for $u, $u2;
my $session = LJ::Session->create( $u, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;

my $evt       = LJ::Event::AddedToCircle->new( $u2, $u, 2 );
my $seed_item = $u->notification_inbox->enqueue( event => $evt );
my $qid       = $seed_item->qid;

test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };

    # --- Canonical native routes resolve directly for a logged-in user ---
    for my $path (qw(/inbox /inbox/ /inbox/index.bml)) {
        my $res = $cb->( GET $path );
        is( $res->code, 200, "$path resolves natively (not a redirect, not 404)" );
        ok( !$res->header('Location'), "$path is not a redirect" );
        like( $res->content, qr/id=["']inbox["']/, "$path renders the native inbox page" );
    }

    # singleentry filtering via query args continues to work at the
    # canonical URL, matching how JournalNewComment.pm links to it.
    my $single = $cb->( GET "/inbox/?view=singleentry&itemid=$qid" );
    is( $single->code, 200, '/inbox/?view=singleentry&itemid= resolves natively' );
    like( $single->content, qr/id=["']inbox["']/,
        'singleentry view renders the native inbox page' );

    for my $path (qw(/inbox/compose /inbox/compose.bml)) {
        my $res = $cb->( GET $path );
        is( $res->code, 200, "$path resolves natively" );
        ok( !$res->header('Location'), "$path is not a redirect" );
        my $token = form_token( $res->content );
        ok( $token, "$path renders a real compose form with a CSRF token" );
    }

    my $msg = LJ::Message->new(
        {
            journalid => $u2->id,
            otherid   => $u->id,
            msgid     => LJ::alloc_global_counter('M'),
            timesent  => time(),
            subject   => 'cutover fixture',
            body      => 'body',
        }
    );
    $msg->save_to_db or die 'unable to save cutover markspam fixture message';
    for my $path ( '/inbox/markspam', '/inbox/markspam.bml' ) {
        my $res = $cb->( GET "$path?msgid=" . $msg->msgid );
        is( $res->code, 200, "$path resolves natively" );
        ok( !$res->header('Location'), "$path is not a redirect" );
        like( $res->content, qr/msgid/, "$path renders the native markspam confirmation form" );
    }

    # --- POST with form auth works end to end at the canonical routes ---
    my $index_get   = $cb->( GET '/inbox' );
    my $index_token = form_token( $index_get->content );
    ok( $index_token, 'canonical /inbox supplies a CSRF token' );
    my $post_res = $cb->(
        POST '/inbox',
        Content => [ mark_read => 1, "check_$qid" => $qid, lj_form_auth => $index_token ],
    );
    is( $post_res->code, 200, 'POST to canonical /inbox with form auth succeeds' );
    ok( !$post_res->header('Location'), 'POST to canonical /inbox is not a redirect' );

    # --- Retained /inbox/new* links redirect to canonical URLs, keeping args ---
    for my $case (
        [ '/inbox/new?view=circle',                   qr{/inbox(?:\?|$)} ],
        [ '/inbox/new/compose?user=' . $u2->user,     qr{/inbox/compose(?:\?|$)} ],
        [ '/inbox/new/markspam?msgid=' . $msg->msgid, qr{/inbox/markspam(?:\?|$)} ],
        )
    {
        my ( $old_path, $expected ) = @$case;
        my $res = $cb->( GET $old_path );
        ok( $res->is_redirect, "$old_path redirects" );
        my $location = $res->header('Location') || '';
        like( $location, $expected, "$old_path redirects to its canonical URL" );
    }

    # Confirm the redirected-to query args are the actual submitted ones,
    # not merely present.
    my $view_redirect = $cb->( GET '/inbox/new?view=circle' );
    like( $view_redirect->header('Location') || '',
        qr/[?&]view=circle\b/,
        '/inbox/new?view=circle preserves the view argument across the redirect' );
    my $compose_redirect = $cb->( GET '/inbox/new/compose?user=' . $u2->user );
    like(
        $compose_redirect->header('Location') || '',
        qr/[?&]user=\Q@{[ $u2->user ]}\E\b/,
        '/inbox/new/compose?user= preserves the user argument across the redirect'
    );

    # --- Anonymous gets the login response, not the native page ---
    my $anon = $send->( GET '/inbox' );
    ok( $anon->is_redirect, 'anonymous /inbox is redirected rather than rendered' );
    like( $anon->header('Location') || '', qr{/login\b},
        'anonymous /inbox is redirected to login' );

    # --- The no-JS bookmark toggle link mutates via GET and is now the
    # primary route at cutover, so it must require its own CSRF token. ---
    # notification_inbox caches its bookmark set on the user object, so a
    # fresh reload is required to observe a mutation made by a separate
    # (server-side) user object in the same process.
    my $fresh_is_bookmark =
        sub { LJ::load_userid( $u->id, 1 )->notification_inbox->is_bookmark($qid) };

    my $before     = $fresh_is_bookmark->();
    my $bad_toggle = $cb->( GET "/inbox/?bookmark_off=$qid" );
    is( $bad_toggle->code, 200, 'bookmark toggle without a token still renders' );
    is( $fresh_is_bookmark->(), $before,
        'bookmark toggle without a token does not change bookmark state' );

    my $good_toggle =
        $cb->( GET "/inbox/?bookmark_off=$qid&lj_form_auth=" . LJ::eurl($index_token) );
    ok( $good_toggle->is_redirect,
        'a successful token-bearing bookmark toggle redirects rather than re-rendering' );
    my $clean_location = $good_toggle->header('Location') || '';
    unlike( $clean_location, qr/bookmark_(?:on|off)=/,
        'the redirect after a bookmark toggle drops the toggle param' );
    unlike( $clean_location, qr/lj_form_auth=/,
        'the redirect after a bookmark toggle drops the CSRF token from the address bar' );
    is( $fresh_is_bookmark->(), 1,
        'bookmark toggle with a valid token actually changes bookmark state' );

    # notification_inbox/NotificationItem singletons cache on the user
    # object, so a fresh reload is required to see a server-side mutation.
    my $fresh_item_read =
        sub { LJ::NotificationItem->new( LJ::load_userid( $u->id, 1 ), $_[0] )->read };

    # --- REQUIRED: templates/code no longer point at /inbox/new, which is a
    # redirect. Submit the *rendered* form via its own action attribute --
    # this is exactly what a browser does, and is what silently dropped a
    # POST body when the action still said /inbox/new. ---
    my $another_evt  = LJ::Event::AddedToCircle->new( $u2, $u, 2 );
    my $another_item = $u->notification_inbox->enqueue( event => $another_evt );
    my $another_qid  = $another_item->qid;

    my $rendered = $cb->( GET '/inbox' );
    my ($actions_form) =
        grep { $_->find_input('mark_read') }
        HTML::Form->parse( $rendered->content, 'http://localhost/inbox' );
    ok( $actions_form, 'the rendered no-JS actions form parses' );
    like( $actions_form->action, qr{^https?://[^/]+/inbox$},
        'the rendered actions form posts to the canonical URL, not /inbox/new' );
    ok(
        $actions_form->find_input("check_$another_qid"),
        'the rendered form has a checkbox for the seeded item'
    );
    $actions_form->value( "check_$another_qid" => $another_qid );
    my $submitted = $cb->( $actions_form->click('mark_read') );
    is( $submitted->code, 200, 'submitting the rendered actions form is handled natively' );
    ok( $fresh_item_read->($another_qid),
        'submitting the rendered actions form actually marks the item read' );

    # --- REQUIRED: a POST straight to a retained /inbox/new* link (a tab
    # left open from before cutover) must not be silently dropped by a
    # redirect; it must be handled the same as the canonical URL. ---
    my $stale_item =
        $u->notification_inbox->enqueue( event => LJ::Event::AddedToCircle->new( $u2, $u, 2 ) );
    my $stale_qid  = $stale_item->qid;
    my $stale_post = $cb->(
        POST '/inbox/new',
        Content => [
            mark_read          => 1,
            "check_$stale_qid" => $stale_qid,
            lj_form_auth       => $index_token,
        ],
    );
    is( $stale_post->code, 200, 'POST straight to /inbox/new is handled natively, not redirected' );
    ok( !$stale_post->header('Location'), 'POST straight to /inbox/new is not a redirect' );
    ok( $fresh_item_read->($stale_qid),
        'POST straight to /inbox/new actually performs the mutation, not silently dropped' );

    my $stale_compose_get   = $cb->( GET '/inbox/compose' );
    my $stale_compose_token = form_token( $stale_compose_get->content );
    my $stale_compose_post  = $cb->(
        POST '/inbox/new/compose',
        Content => [
            mode         => 'send',
            msg_to       => $u2->user,
            msg_subject  => 'stale tab subject',
            msg_body     => 'stale tab body',
            lj_form_auth => $stale_compose_token,
        ],
    );
    ok( $stale_compose_post->is_redirect,
'POST straight to /inbox/new/compose is handled natively through to its own success redirect'
    );
    like( $stale_compose_post->header('Location') || '',
        qr{/inbox$},
        'POST straight to /inbox/new/compose actually sends, landing on the success redirect' );

    # --- Reviewer follow-up: $r->uri is the raw path, so an explicit old
    # link's .bml suffix (a real historical URL shape) must still
    # canonicalize on GET rather than quietly rendering at the old path. ---
    my $bml_suffix_redirect = $cb->( GET '/inbox/new.bml?view=circle' );
    ok( $bml_suffix_redirect->is_redirect,
        'GET /inbox/new.bml still redirects to the canonical URL' );
    like( $bml_suffix_redirect->header('Location') || '',
        qr{/inbox(?:\?|$)}, '/inbox/new.bml redirects to /inbox' );

    # --- Reviewer follow-up: the trailing-slash form must not fall into
    # routing's own default page/ -> page redirect, which is exactly as
    # body-dropping for a POST as the register_redirect this package removed. ---
    my $trailing_slash_item =
        $u->notification_inbox->enqueue( event => LJ::Event::AddedToCircle->new( $u2, $u, 2 ) );
    my $trailing_slash_qid  = $trailing_slash_item->qid;
    my $trailing_slash_post = $cb->(
        POST '/inbox/new/',
        Content => [
            mark_read                   => 1,
            "check_$trailing_slash_qid" => $trailing_slash_qid,
            lj_form_auth                => $index_token,
        ],
    );
    is( $trailing_slash_post->code,
        200, 'POST to /inbox/new/ (trailing slash) is handled natively, not redirected' );
    ok( !$trailing_slash_post->header('Location'),
        'POST to /inbox/new/ (trailing slash) is not a redirect' );
    ok( $fresh_item_read->($trailing_slash_qid),
        'POST to /inbox/new/ (trailing slash) actually performs the mutation' );

    my $trailing_slash_get = $cb->( GET '/inbox/new/?view=circle' );
    ok( $trailing_slash_get->is_redirect, 'GET /inbox/new/ (trailing slash) still redirects' );
    like( $trailing_slash_get->header('Location') || '',
        qr{/inbox(?:\?|$)}, '/inbox/new/ redirects to /inbox' );
};

# --- No user_in_beta('inbox') check remains outside the retained .bml page ---
{
    my @offenders;
    my $inbox_bml = "$ENV{LJHOME}/htdocs/inbox/index.bml";
    find(
        {
            wanted => sub {
                return unless -f $_ && /\.(?:pm|pl|tt)$/;
                return if $_ eq $inbox_bml;
                open my $fh, '<', $_ or return;
                local $/;
                my $content = <$fh>;
                push @offenders, $File::Find::name
                    if $content =~ /user_in_beta\s*\(\s*\S+\s*(?:=>|,)\s*["']inbox["']/;
            },
            no_chdir => 1,
        },
        "$ENV{LJHOME}/cgi-bin",
        "$ENV{LJHOME}/views",
    );
    is_deeply( \@offenders, [],
        'no user_in_beta("inbox") check remains outside the retained .bml page' );
}

# --- No stray "/inbox/new" reference remains outside the deliberate old-link
# plumbing (route registration and the in-handler redirect-or-fall-through
# check); every user-visible link/form must point at a canonical URL. ---
{
    my @offenders;
    find(
        {
            wanted => sub {
                return unless -f $_ && /\.tt$/;
                open my $fh, '<', $_ or return;
                local $/;
                my $content = <$fh>;
                push @offenders, "$File::Find::name (template)"
                    if $content =~ m{/inbox/new\b};
            },
            no_chdir => 1,
        },
        "$ENV{LJHOME}/views/inbox",
    );

    # Scanned as whole-file text (not line-by-line): a register_string(...)
    # call for a longer path name wraps across lines, and a naive per-line
    # scan would misreport its continuation line as a stray reference.
    open my $fh, '<', "$ENV{LJHOME}/cgi-bin/DW/Controller/Inbox.pm" or die $!;
    local $/;
    my $inbox_pm = <$fh>;
    close $fh;
    ( my $scrubbed = $inbox_pm ) =~ s/^\s*#.*$//mg;
    $scrubbed =~ s/DW::Routing->register_string\s*\([^;]*?\)\s*;//gs;
    $scrubbed =~ s/_redirect_old_get\([^;]*?\)/_redirect_old_get(...)/gs;
    push @offenders,
        'cgi-bin/DW/Controller/Inbox.pm (unexpected reference outside the deliberate plumbing)'
        if $scrubbed =~ m{/inbox/new\b};
    is_deeply( \@offenders, [],
'no stray /inbox/new reference remains outside route registration and the redirect-or-native check'
    );
}

# --- W3: the legacy .bml pages are gone from disk, but their URLs (routing
# runs before the BML file-resolution fallback) still resolve natively
# rather than falling through to a 404. ---
{
    for my $deleted (
        qw(htdocs/inbox/index.bml htdocs/inbox/compose.bml htdocs/inbox/markspam.bml
        htdocs/inbox/index.bml.text htdocs/inbox/compose.bml.text)
        )
    {
        ok( !-e "$ENV{LJHOME}/$deleted", "$deleted no longer exists on disk" );
    }

    test_psgi $app, sub {
        my $send = shift;
        my $cb = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };

        my $post_deletion_msg = LJ::Message->new(
            {
                journalid => $u2->id,
                otherid   => $u->id,
                msgid     => LJ::alloc_global_counter('M'),
                timesent  => time(),
                subject   => 'post-deletion cutover fixture',
                body      => 'body',
            }
        );
        $post_deletion_msg->save_to_db
            or die 'unable to save post-deletion markspam fixture message';

        for my $path (qw(/inbox/index.bml /inbox/compose.bml /inbox/markspam.bml)) {
            my $res = $cb->(
                $path =~ /markspam/
                ? GET "$path?msgid=" . $post_deletion_msg->msgid
                : GET $path
            );
            is( $res->code, 200,
                "$path still resolves natively now that the underlying file is gone" );
        }

        # A genuinely unregistered path under /inbox must still 404 rather
        # than routing permissively resolving anything under the prefix.
        my $bogus = $cb->( GET '/inbox/this-path-was-never-registered' );
        is( $bogus->code, 404, 'an unregistered /inbox/* path still 404s' );
    };
}

done_testing;
