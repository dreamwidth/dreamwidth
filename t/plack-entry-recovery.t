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

    subtest 'exact submitted text survives HTML escaping, byte-for-byte' => sub {
        my $subject = "Recovery subject \x{00e9}\x{1f600} & <b>bold</b>";
        my $body =
            "\nline one\r\nline two <b>bold</b> & 'quote' </textarea><script>window.__x=1</script>";
        my $req = POST '/update',
            Content =>
            [ subject => 'discarded', subject => $subject, event => $body ];    # repeated field
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is( $res->code, 200 );
        is( textarea_text( $res->content, 'recover-subject' ),
            $subject,
            'a repeated subject field keeps its last value, HTML-escaped Unicode intact' );
        is(
            textarea_text( $res->content, 'recover-body' ),
            $body,
'body preserves a leading newline, CRLF, markup, and a closing-textarea/script byte-for-byte'
        );
        unlike(
            $res->content,
            qr/<script>window\.__x=1<\/script>/,
            'the injected script never appears as live, unescaped JavaScript'
        );

        my $placeholder_res =
            $send->( POST '/update', Content => [ subject => 'Enter a subject' ] );   # no event key
        is(
            textarea_text( $placeholder_res->content, 'recover-subject' ),
            'Enter a subject',
            'a placeholder-equal subject is shown as submitted, not blanked'
        );
        is( textarea_text( $placeholder_res->content, 'recover-body' ),
            '', 'a missing body renders an empty box, inventing no text' );
        like(
            $placeholder_res->content,
            qr/No entry body was submitted/,
            'a missing (never-submitted) body gets a distinct missing-body note'
        );

        my $empty_res = $send->( POST '/update', Content => [ subject => '', event => '' ] );
        is( textarea_text( $empty_res->content, 'recover-body' ),
            '', 'an explicitly empty submitted body also renders an empty box' );
        unlike(
            $empty_res->content,
            qr/No entry body was submitted/,
            'an explicitly empty (present) body is distinguished from a missing one'
        );
    };

    subtest 'no sensitive field is echoed, nothing is written, and the response is not cached' =>
        sub {
        $owner->set_draft_text('recovery draft sentinel');
        my $draft_before = $owner->draft_text;
        my ($count_before) = $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?',
            undef, $owner->userid );

        my %markers = (
            password              => 'MARKER-password',
            user                  => 'MARKER-user',
            usejournal            => 'MARKER-usejournal',
            prop_xpost_password_2 => 'MARKER-xpost-password',
            prop_xpost_chal_2     => 'MARKER-xpost-chal',
            prop_xpost_resp_2     => 'MARKER-xpost-resp',
        );
        my $req = POST '/update', Content => [
            subject      => 'Marker subject',
            event        => 'Marker body',
            lj_form_auth => 'not-a-real-token',    # expired/bogus: must not block this response
            %markers,
        ];
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is( $res->code, 200, 'a bogus lj_form_auth does not block the recovery page' );
        is(
            textarea_text( $res->content, 'recover-subject' ),
            'Marker subject',
            'the submitted subject still comes through'
        );
        for my $marker ( values %markers ) {
            unlike( $res->content, qr/\Q$marker\E/, "a submitted $marker is never echoed back" );
        }
        like( $res->header('Cache-Control') // '', qr/no-store/, 'Cache-Control: no-store is set' );
        is( $owner->draft_text, $draft_before, 'the draft is left untouched' );
        my ($count_after) = $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?',
            undef, $owner->userid );
        is( $count_after, $count_before, 'no entry is created by the recovery POST' );
        };

    subtest 'both routes and their .bml aliases reach the page for anyone, logged in or out' =>
        sub {
        for my $path (qw(/update /update.bml)) {
            my $req = POST $path, Content => [ subject => "Alias $path", event => 'b' ];
            $req->header( Cookie => $owner_cookie );
            is( $send->($req)->code, 200, "$path POST reaches the recovery page" );
        }
        is( $send->( POST '/update', Content => [ subject => 'Anon', event => 'b' ] )->code,
            200, 'a logged-out POST reaches the same recovery page, with no auth requirement' );

        # an itemid POST never looks up or exposes the real entry, and never
        # checks who is asking -- the native edit route enforces auth on click
        my $entry = $owner->t_post_fake_entry(
            subject => 'STORED-MARKER-subject',
            body    => 'STORED-MARKER-body',
        );
        my $stored_body = $entry->event_raw;
        my $edit_href =
            qr{href="[^"]*/entry/\Q@{[ $owner->user ]}\E/\Q@{[ $entry->ditemid ]}\E/edit"};

        my $owner_req = POST '/editjournal?itemid=' . $entry->ditemid,
            Content => [ subject => 'Owner edit subject', event => 'b' ];
        $owner_req->header( Cookie => $owner_cookie );
        my $owner_res = $send->($owner_req);
        unlike( $owner_res->content, qr/STORED-MARKER/, 'the owner never sees the stored text' );
        like( $owner_res->content, $edit_href, 'the owner gets the correct native edit link' );

        my $outsider_req =
            POST '/editjournal.bml?itemid=' . $entry->ditemid . '&usejournal=' . $owner->user,
            Content => [ subject => 'Outsider edit subject', event => 'b' ];
        $outsider_req->header( Cookie => cookie_for($outsider) );
        my $outsider_res = $send->($outsider_req);
        is( $outsider_res->code, 200,
            'a non-owner gets the same page, not an authorization check' );
        unlike( $outsider_res->content, qr/STORED-MARKER/,
            'the non-owner never sees the stored text either' );
        like( $outsider_res->content, $edit_href,
            'the non-owner gets the same real edit link; the edit route itself will enforce auth' );

        LJ::Entry::reset_singletons();
        is( LJ::Entry->new( $owner, ditemid => $entry->ditemid )->event_raw,
            $stored_body, 'the real entry is left completely unchanged by either POST' );
        };
};

done_testing;
