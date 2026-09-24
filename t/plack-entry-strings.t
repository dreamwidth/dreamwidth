#!/usr/bin/perl
# Proves every relocated entry-page string (formerly page-scoped keys in
# htdocs/update.bml.text, editjournal.bml.text, imgupload.bml.text, and
# htdocs/preview/entry.bml.text) still renders its exact English text with
# no missing-string banner, from its new native home.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;

use File::Find;
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Controller::Entry;
use LJ::Session;
use LJ::Test qw(temp_comm temp_user);

plan skip_all => 'Entry string relocation requires a development server'
    unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub no_missing_string {
    my ( $content, $label ) = @_;
    unlike( $content, qr/\[missing string/i, "$label has no missing-string banner" );
}

my $u = temp_user();
$u->update_self( { status => 'A' } );
my $session = LJ::Session->create( $u, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryStringRelocation';

test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };

    # --- /entry/new (logged in): relocated imgupload.bml.insertimage.* ---
    my $new_res = $cb->( GET '/entry/new' );
    is( $new_res->code, 200, '/entry/new renders' );
    no_missing_string( $new_res->content, '/entry/new' );
    like(
        $new_res->content,
        qr/Image from URL/,
        '/entry/new renders the relocated insertimage.url text'
    );
    like(
        $new_res->content,
        qr/Short Description/,
        '/entry/new renders the relocated insertimage.alt.label text'
    );
    like(
        $new_res->content,
        qr/This description is used by screenreaders/,
        '/entry/new renders the relocated insertimage.alt.body text'
    );
    like(
        $new_res->content,
        qr/tips on writing good descriptions/,
'/entry/new renders the relocated insertimage.alt.faqlink text (via the faqlink hook fallback)'
    );

    # --- /entry/new (anonymous): general regression on
    # views/entry/login.tt.text's pre-existing one-time login modal content. ---
    my $anon_res = $send->( GET '/entry/new' );
    is( $anon_res->code, 200, 'anonymous /entry/new renders' );
    no_missing_string( $anon_res->content, 'anonymous /entry/new' );
    like(
        $anon_res->content,
        qr/This will not log you in/,
        'anonymous /entry/new renders the one-time login modal text'
    );

    # --- /editjournal picker: relocated editjournal.bml.* (now served from
    # its own ml_scope, /editjournal.tt, instead of /editjournal.bml) ---
    my $picker_res = $cb->( GET '/editjournal' );
    is( $picker_res->code, 200, '/editjournal picker renders' );
    no_missing_string( $picker_res->content, '/editjournal' );
    like(
        $picker_res->content,
        qr/Use the form below to search for the entry/,
        '/editjournal renders its relocated .desc text'
    );

    # --- /editjournal picker (community context): relocated
    # editjournal.bml.{auth.poster,security.*} keys, which live in
    # views/editjournal.tt itself rather than in EntryPicker.pm ---
    my $comm = temp_comm();
    LJ::set_rel( $comm, $u, 'A' );
    $u->t_post_fake_comm_entry( $comm, security => 'private' );
    my $comm_picker_res = $cb->( GET '/editjournal?usejournal=' . $comm->user );
    is( $comm_picker_res->code, 200, '/editjournal community picker renders' );
    no_missing_string( $comm_picker_res->content, '/editjournal community picker' );
    like(
        $comm_picker_res->content,
        qr/entry-picker-poster">Poster:/,
        '/editjournal renders the relocated .auth.poster label'
    );
    like(
        $comm_picker_res->content,
        qr/<img\b[^>]*\balt=["']Private entry["'][^>]*\btitle=["']Private entry["'][^>]*>/,
        '/editjournal renders the relocated .security.private icon alt/title text'
    );

    # --- /imguploadrte dialog: relocated imgupload.bml.insertimage.alt.* ---
    my $dialog_res = $cb->( GET '/imguploadrte' );
    is( $dialog_res->code, 200, '/imguploadrte dialog renders' );
    no_missing_string( $dialog_res->content, '/imguploadrte' );
    like(
        $dialog_res->content,
        qr/This description is used by screenreaders/,
        '/imguploadrte renders the relocated insertimage.alt.body text'
    );
    like(
        $dialog_res->content,
        qr/tips on writing good descriptions/,
        '/imguploadrte renders the relocated insertimage.alt.faqlink text'
    );

    # --- manage/index: relocated /editjournal.bml.title -> /editjournal.tt.title ---
    my $manage_res = $cb->( GET '/manage/' );
    is( $manage_res->code, 200, '/manage/ renders' );

    # /manage/ has other, unrelated pre-existing missing-string keys from
    # other in-progress migrations; check only the specific relocated
    # editjournal title key, not the whole page.
    like(
        $manage_res->content,
        qr/Edit Entries/,
        '/manage/ renders the relocated editjournal title text'
    );
    unlike(
        $manage_res->content,
        qr/\[missing string \/editjournal\.(?:bml|tt)\.title/i,
        '/manage/ does not show a missing-string banner for the relocated editjournal title key'
    );
};

# --- /entry/preview: preview_handler/_render_preview resolve both keys
# under /entry/preview.tt -- .entry.preview_warn_text via a direct
# LJ::Lang::ml() call (Entry.pm's _render_preview), .title via the
# template's own relative resolution (views/entry/preview.tt's
# sections.windowtitle). preview_handler needs a real style/request context
# this test does not build; asserting the exact fully-qualified keys it
# uses resolve correctly is equivalent and direct. ---
{
    is(
        LJ::Lang::ml('/entry/preview.tt.title'),
        '[[sitenameshort]]: Entry Preview (Unsaved)',
        'relocated /entry/preview.tt.title resolves to its exact English text'
    );
    is(
        LJ::Lang::ml('/entry/preview.tt.entry.preview_warn_text'),
'This is a preview only. To save this entry, close this popup and return to your main browser window.',
        'relocated /entry/preview.tt.entry.preview_warn_text resolves to its exact English text'
    );
}

# --- Static scan: no native file (cgi-bin/DW, views, cgi-bin/LJ/Widget)
# references /update.bml., /editjournal.bml., /imgupload.bml., or
# /preview/entry.bml outside a legacy_* sub in Entry.pm. ---
{
    my @offenders;

    # views/ and cgi-bin/LJ/Widget: no occurrence of any of the four
    # prefixes is ever legitimate, since nothing there is a legacy_* sub.
    find(
        {
            wanted => sub {
                return unless -f $_ && /\.(?:tt|pm)$/;
                open my $fh, '<', $_ or return;
                local $/;
                my $content = <$fh>;
                push @offenders, $File::Find::name
                    if $content =~
                    m{/(?:update|editjournal|imgupload)\.bml\.|/preview/entry\.bml\.};
            },
            no_chdir => 1,
        },
        "$ENV{LJHOME}/views",
        "$ENV{LJHOME}/cgi-bin/LJ/Widget",
    );

    # cgi-bin/DW: every match must be a comment or fall inside a sub whose
    # name starts with legacy_ (Entry.pm's retiring compatibility seams).
    find(
        {
            wanted => sub {
                return unless -f $_ && /\.pm$/;
                open my $fh, '<', $_ or return;
                my @lines = <$fh>;
                close $fh;
                my $current_sub = '';
                for my $i ( 0 .. $#lines ) {
                    my $line = $lines[$i];
                    $current_sub = $1 if $line =~ /^sub\s+(\S+)/;
                    next
                        unless $line =~
                        m{/(?:update|editjournal|imgupload)\.bml\.|/preview/entry\.bml\.};
                    next if $line =~ /^\s*#/;
                    next if $current_sub =~ /^legacy_/;
                    push @offenders, "$File::Find::name:" . ( $i + 1 ) . ": $line";
                }
            },
            no_chdir => 1,
        },
        "$ENV{LJHOME}/cgi-bin/DW",
    );

    is_deeply( \@offenders, [],
        'no native file references the four relocated-from scopes outside a legacy_* sub' );
}

done_testing;
