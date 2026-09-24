#!/usr/bin/perl
# The subject/body recovery page shown for a stale old-editor POST to
# /update or /editjournal?itemid: it must echo back only the exact
# submitted subject and body, verbatim and HTML-safe, and never write
# anything.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use Encode qw(decode_utf8);
use HTTP::Request::Common;
use HTML::Entities qw(decode_entities);
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Entry;
use LJ::Session;
use LJ::Test qw(temp_user);
plan skip_all => 'Recovery integration requires a development server' unless $LJ::IS_DEV_SERVER;

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

# recovers the exact submitted text a named textarea encloses: the response
# body is UTF-8-encoded bytes, so this decodes entities first (pure ASCII,
# byte-safe) and then decodes UTF-8 to get back the original character string
sub textarea_text {
    my ( $content, $id ) = @_;
    my ($raw) = $content =~ m{<textarea id="\Q$id\E"[^>]*>\n(.*?)</textarea>}s;
    return undef unless defined $raw;
    return decode_utf8( decode_entities($raw) );
}

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $owner_cookie = cookie_for($owner);
my $outsider     = temp_user();
$outsider->update_self( { status => 'A' } );
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryRecovery';

test_psgi $app, sub {
    my $send = shift;

    subtest 'exact-byte round-trip of markup, Unicode, CRLF, and a closing-textarea sequence' =>
        sub {
        my $subject = "Recovery subject \x{00e9}\x{1f600} & <b>bold</b>";
        my $body =
"line one\r\nline two <b>bold</b> & 'quote' \"dq\" </textarea><script>window.__x=1</script>";
        my $req = POST '/update', Content => [ subject => $subject, event => $body ];
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is( $res->code, 200, 'recovery page renders' );

        is( textarea_text( $res->content, 'recover-subject' ),
            $subject, 'subject round-trips byte-for-byte, including Unicode' );
        is( textarea_text( $res->content, 'recover-body' ),
            $body, 'body round-trips byte-for-byte, including CRLF and markup' );
        unlike( $res->content, qr/<\/textarea><script/,
            'the closing-textarea/script sequence never breaks out of the textarea' );
        unlike(
            $res->content,
            qr/<script>window\.__x=1<\/script>/,
            'the injected script never appears as live, unescaped JavaScript'
        );
        };

    subtest 'the old subject placeholder text is preserved literally, not cleared' => sub {
        my $req = POST '/update',
            Content => [ subject => 'Enter a subject', event => 'placeholder body' ];
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is(
            textarea_text( $res->content, 'recover-subject' ),
            'Enter a subject',
            'placeholder-equal subject is shown as submitted, not blanked'
        );
    };

    subtest 'an empty submitted field renders an empty box; a missing one adds a note' => sub {
        my $req = POST '/update', Content => [ subject => '', event => '' ];
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is( textarea_text( $res->content, 'recover-subject' ),
            '', 'an empty submitted subject renders an empty box' );
        is( textarea_text( $res->content, 'recover-body' ),
            '', 'an empty submitted body renders an empty box' );
        unlike(
            $res->content,
            qr/No entry body was submitted/,
            'an explicitly empty (but present) body gets no missing-body note'
        );

        my $req2 = POST '/update', Content => [ subject => 'Subject only' ];
        $req2->header( Cookie => $owner_cookie );
        my $res2 = $send->($req2);
        is( textarea_text( $res2->content, 'recover-body' ),
            '', 'a missing body still renders an empty box, inventing no text' );
        like(
            $res2->content,
            qr/No entry body was submitted/,
            'a missing (never-submitted) body gets the missing-body note'
        );
    };

    subtest 'a repeated form field resolves to its last submitted value' => sub {
        my $req = POST '/update',
            Content => [ subject => 'first subject', subject => 'second subject', event => 'b' ];
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is(
            textarea_text( $res->content, 'recover-subject' ),
            'second subject',
            'a repeated subject field keeps the last value'
        );
    };

    subtest 'no expired or missing form-auth token blocks the recovery page' => sub {
        my $req = POST '/update',
            Content => [
            subject       => 'Form-auth subject',
            event         => 'Form-auth body',
            lj_form_auth  => 'not-a-real-token',
            'action:post' => 'Post',
            ];
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is( $res->code, 200, 'a bogus lj_form_auth does not block the recovery page' );
        is(
            textarea_text( $res->content, 'recover-subject' ),
            'Form-auth subject',
            'the submitted subject still comes through'
        );
    };

    subtest 'no sensitive or unrelated request field is ever carried into the page' => sub {
        my %markers = (
            password              => 'MARKER-password',
            user                  => 'MARKER-user',
            usejournal            => 'MARKER-usejournal',
            prop_xpost_password_2 => 'MARKER-xpost-password',
            prop_xpost_chal_2     => 'MARKER-xpost-chal',
            prop_xpost_resp_2     => 'MARKER-xpost-resp',
            lj_form_auth          => 'MARKER-form-auth',
        );
        my $req = POST '/update',
            Content => [ subject => 'Marker subject', event => 'Marker body', %markers ];
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is( $res->code, 200 );
        for my $field ( sort keys %markers ) {
            unlike( $res->content, qr/\Q$markers{$field}\E/,
                "the submitted $field is never echoed into the response" );
        }
    };

    subtest 'no draft or entry is ever written by the recovery POST' => sub {
        $owner->set_draft_text('recovery draft sentinel');
        my $draft_before = $owner->draft_text;
        my ($count_before) = $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?',
            undef, $owner->userid );

        my $req = POST '/update',
            Content => [ subject => 'No-write subject', event => 'No-write body' ];
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is( $res->code, 200 );

        is( $owner->draft_text, $draft_before, 'the draft text is left untouched' );
        my ($count_after) = $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?',
            undef, $owner->userid );
        is( $count_after, $count_before, 'no entry is created by the recovery POST' );
    };

    subtest 'the response is never cacheable, since it can echo submitted content' => sub {
        my $req = POST '/update', Content => [ subject => 'Cache subject', event => 'Cache body' ];
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        like( $res->header('Cache-Control') // '', qr/no-store/, 'Cache-Control: no-store is set' );
    };

    subtest 'logged-out POSTs get the same recovery page, with no auth requirement' => sub {
        my $req = POST '/update', Content => [ subject => 'Anon subject', event => 'Anon body' ];
        my $res = $send->($req);
        is( $res->code, 200, 'a logged-out old-schema POST still renders the recovery page' );
        is( textarea_text( $res->content, 'recover-subject' ),
            'Anon subject', 'the submitted subject still comes through logged out' );
    };

    subtest 'both .bml aliases reach the same recovery page' => sub {
        my $req = POST '/update.bml',
            Content => [ subject => 'Alias update', event => 'Alias body' ];
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is( $res->code, 200, '/update.bml POST renders the recovery page' );
        is( textarea_text( $res->content, 'recover-subject' ),
            'Alias update', '/update.bml preserves the submitted subject' );

        my $entry = $owner->t_post_fake_entry(
            subject => 'Alias fixture subject',
            body    => 'Alias fixture body',
        );
        my $edit_req = POST '/editjournal.bml?itemid=' . $entry->ditemid,
            Content => [ subject => 'Alias editjournal', event => 'Alias edit body' ];
        $edit_req->header( Cookie => $owner_cookie );
        my $edit_res = $send->($edit_req);
        is( $edit_res->code, 200, '/editjournal.bml?itemid POST renders the recovery page' );
        is(
            textarea_text( $edit_res->content, 'recover-subject' ),
            'Alias editjournal',
            '/editjournal.bml preserves the submitted subject'
        );
    };

    subtest 'an itemid POST for an owned entry links to that entry\'s native edit form' => sub {
        my $entry = $owner->t_post_fake_entry(
            subject => 'STORED-MARKER-owned-subject',
            body    => 'STORED-MARKER-owned-body',
        );
        my $stored_body = $entry->event_raw;

        my $req = POST '/editjournal?itemid=' . $entry->ditemid,
            Content => [ subject => 'Owned edit subject', event => 'Owned edit body' ];
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is( $res->code, 200 );
        unlike( $res->content, qr/STORED-MARKER/,
            'the entry\'s stored (unsubmitted) text is never shown' );
        is(
            textarea_text( $res->content, 'recover-subject' ),
            'Owned edit subject',
            'the submitted subject is shown instead'
        );
        like(
            $res->content,
            qr{href="[^"]*/entry/\Q@{[ $owner->user ]}\E/\Q@{[ $entry->ditemid ]}\E/edit"},
            'the page links to the native edit form for this exact entry'
        );

        LJ::Entry::reset_singletons();
        is( LJ::Entry->new( $owner, ditemid => $entry->ditemid )->event_raw,
            $stored_body, 'the real entry is left completely unchanged' );
    };

    subtest 'an itemid POST for another user\'s entry also links to its native edit form' => sub {
        my $entry = $owner->t_post_fake_entry(
            subject => 'STORED-MARKER-outsider-subject',
            body    => 'STORED-MARKER-outsider-body',
        );
        my $stored_body = $entry->event_raw;

        my $req = POST '/editjournal?itemid=' . $entry->ditemid . '&usejournal=' . $owner->user,
            Content => [ subject => 'Outsider edit subject', event => 'Outsider edit body' ];
        $req->header( Cookie => cookie_for($outsider) );
        my $res = $send->($req);
        is( $res->code, 200,
            'a non-owner also gets the recovery page, not an authorization check' );
        unlike( $res->content, qr/STORED-MARKER/, 'the real entry\'s stored text is never shown' );
        is(
            textarea_text( $res->content, 'recover-subject' ),
            'Outsider edit subject',
            'the submitted subject is shown instead'
        );
        like(
            $res->content,
            qr{href="[^"]*/entry/\Q@{[ $owner->user ]}\E/\Q@{[ $entry->ditemid ]}\E/edit"},
'the link still names the entry\'s real owner and itemid; auth is enforced on click, not here'
        );

        LJ::Entry::reset_singletons();
        is( LJ::Entry->new( $owner, ditemid => $entry->ditemid )->event_raw,
            $stored_body, 'the real entry is left completely unchanged' );
    };
};

done_testing;
