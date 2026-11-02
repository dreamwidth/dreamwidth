#!/usr/bin/perl
# t/plack-entry-recovery.t
#
# The subject/body recovery page shown for a stale old-editor POST to
# /update or /editjournal?itemid: it must echo back only the exact
# submitted subject and body, verbatim and HTML-safe, and never write
# anything.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
use strict;
use warnings;
use Test::More;
use Encode qw(decode_utf8);
use HTTP::Request::Common;
use HTML::Entities qw(decode_entities);
use HTML::Form;
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
        my $req = POST '/update', Content => [ subject => $subject, event => $body ];
        $req->header( Cookie => $owner_cookie );
        my $res = $send->($req);
        is( $res->code, 200 );
        is( textarea_text( $res->content, 'recover-subject' ),
            $subject, 'subject keeps HTML-escaped Unicode intact' );
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
        is( LJ::load_userid( $owner->userid, 'force' )->draft_text,
            $draft_before, 'the draft is left untouched' );
        my ($count_after) = $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?',
            undef, $owner->userid );
        is( $count_after, $count_before, 'no entry is created by the recovery POST' );
        };

    subtest 'stale itemid POSTs reach anyone and never expose or change the entry' => sub {
        is( $send->( POST '/update', Content => [ subject => 'Anon', event => 'b' ] )->code,
            200, 'a logged-out POST reaches the recovery page, with no auth requirement' );

        # An itemid POST never looks up the real entry or checks who is asking;
        # the native edit route enforces auth on click.
        my $entry = $owner->t_post_fake_entry(
            subject => 'STORED-MARKER-subject',
            body    => 'STORED-MARKER-body',
        );
        my $outsider_req =
            POST '/editjournal?itemid=' . $entry->ditemid . '&usejournal=' . $owner->user,
            Content => [ subject => 'Outsider edit subject', event => 'b' ];
        $outsider_req->header( Cookie => cookie_for($outsider) );
        my $outsider_res = $send->($outsider_req);
        is( $outsider_res->code, 200, 'a non-owner gets the recovery page' );
        unlike( $outsider_res->content, qr/STORED-MARKER/,
            'the non-owner never sees the stored text' );

        # An old-editor delete click arrives as submit_value; even the owner's
        # valid token must not make it delete.
        my $new_req = GET '/entry/new';
        $new_req->header( Cookie => $owner_cookie );
        my ($form) = grep { $_->find_input('lj_form_auth') }
            HTML::Form->parse( $send->($new_req)->content, 'http://localhost' );
        my $token = $form ? $form->value('lj_form_auth') : undef;
        ok( $token, 'owner has a real form-auth token' );
        my $delete_req = POST '/editjournal?itemid=' . $entry->ditemid,
            Content => [
            mode         => 'init',
            itemid       => $entry->ditemid,
            submit_value => 'action:delete',
            lj_form_auth => $token,
            ];
        $delete_req->header( Cookie => $owner_cookie );
        like(
            $send->($delete_req)->content,
            qr/Nothing here was posted or saved/i,
            'a stale delete POST gets the recovery page'
        );

        LJ::Entry::reset_singletons();
        my $fresh = LJ::Entry->new( $owner, ditemid => $entry->ditemid );
        ok( $fresh->valid, 'a stale delete POST leaves the entry in place' );
        is( $fresh->event_raw, 'STORED-MARKER-body', 'the entry body is unchanged' );
    };
};

done_testing;
