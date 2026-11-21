# t/emailpost.t
#
# Test posting via email.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2013-2018 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More tests => 169;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::EmailPost;
use LJ::Emailpost::Web;

use LJ::Test;
use FindBin qw($Bin);
use File::Temp;
use MIME::Entity;
use MIME::Parser;

local $LJ::T_ALLOW_EMAILPOST = 1;    # override caps

my $u        = temp_user();
my $emailpin = "emailpin123";

my $user_email_info = {
    TEMPUSER   => $u->user,
    EMAILPIN   => $emailpin,
    POSTDOMAIN => "post.$LJ::DOMAIN",
    FROM_EMAIL => 'foo@example.com',
};

# the brian aker example/bug report
my $mime = get_mime( "delspyes", $user_email_info );
ok( $mime, "got delspyes MIME" );

my ( $email_post, $ok, $msg );
my $user = $u->user;

$email_post = DW::EmailPost->get_handler($mime);
$email_post->destination($user);
( $ok, $msg ) = $email_post->process;
ok( !$ok, "not posted" );
like(
    $msg,
    qr/No allowed senders have been saved for your account/,
    "rejected due to no allowed senders"
);
is( $email_post->dequeue, 1, "and it's dequeued" );

LJ::Emailpost::Web::set_allowed_senders( $u, { 'foo@example.com' => { get_errors => 1 } } );
is( $u->prop("emailpost_allowfrom"), "foo\@example.com(E)", "allowed sender set correctly" );

$email_post = DW::EmailPost->get_handler($mime);
$email_post->destination($user);
( $ok, $msg ) = $email_post->process;
ok( !$ok, "not posted" );
like( $msg, qr/Unable to locate your PIN/, "rejected due to no PIN" );
is( $email_post->dequeue, 1, "and it's dequeued" );

$email_post = DW::EmailPost->get_handler($mime);
$email_post->destination("$user+$emailpin");
( $ok, $msg ) = $email_post->process;
ok( !$ok, "not posted" );
like( $msg, qr/Invalid PIN/, "rejected due to invalid PIN" );
is( $email_post->dequeue, 1, "and it's dequeued" );

$u->set_prop( "emailpost_pin",      $emailpin );
$u->set_prop( 'emailpost_security', 'public' );

$email_post = DW::EmailPost->get_handler($mime);
$email_post->destination("$user+$emailpin");
( $ok, $msg ) = $email_post->process;
ok( $ok, "posted" );
like( $msg, qr/Post success/, "posted!" );
is( $email_post->dequeue, 1, "and it's dequeued" );

my $entry = LJ::Entry->new( $u, jitemid => 1 );
ok( $entry->valid, "Entry is valid" );
diag( "Posted to: " . $entry->url );

my $text = $entry->event_raw;
ok( $text !~ qr!http://krow\.livejournal\.com/ 434338\.html!,
    "no space in URLs.  delsp=yes working." );
ok( $text =~ qr!http://krow\.livejournal\.com/434338\.html!,
    "got correct URL in post, all together." );

{
    my $email_post = DW::EmailPost->get_handler( get_mime( "long-subject", $user_email_info ) );
    my ( $ok, $msg ) = $email_post->process;
    ok( $ok, "posted entry with long subject" );
    my $entry = LJ::Entry->new( $u, jitemid => 2 );
    is(
        $entry->subject_raw,
"Here's an entry emailed-in with a long subject (>100 characters) which will end up being truncated s",
        "Entry subject truncated"
    );
}

{
    $u->set_prop( 'opt_whoscreened', 'F' );
    my $foobit = $u->create_trust_group( groupname => 'foo' );
    $u->create_trust_group( groupname => 'foo, bar' );
    my $barbit     = $u->create_trust_group( groupname => 'bar' );
    my $email_post = DW::EmailPost->get_handler( get_mime( "parse-props", $user_email_info ) );
    my ( $ok, $msg ) = $email_post->process;
    ok( $ok, "posted entry with custom settings" ) or diag $msg;
    my $entry    = LJ::Entry->new( $u, jitemid => 3 );
    my $expected = <<'BODY';
For Sweeney Todd: Sweeney/Nellie,
post-canon, pre-canon, everybody lives AU
Unwilling to address: character x reader
post-canon: everyone's alive
post-war: rebuilding
post-security: public
lj-mood: happy
BODY
    chomp $expected;
    is( $entry->event_raw, $expected, "Leading settings removed and body text preserved" );
    is( $entry->security,  'usemask', "Entry security is correct" );
    is( $entry->allowmask, ( 1 << $foobit ) | ( 1 << $barbit ), 'Entry allowmask is correct' );
    is( $entry->prop('current_moodid'), 56, "Entry mood is correct" );
    is( $entry->prop('current_music'), "Jonathan Coulton -- Code Monkey",
        "Entry music is correct" );
    is( $entry->prop('opt_screening'), 'R', 'Entry comment screening is correct' );
}

{
    my $email_post = DW::EmailPost->get_handler( get_mime( "html-headers", $user_email_info ) );
    my ( $ok, $msg ) = $email_post->process;
    ok( $ok, "posted HTML entry with custom settings" ) or diag $msg;
    my $entry = LJ::Entry->new( $u, jitemid => 4 );
    is( $entry->security, 'private', 'Header inside leading HTML wrappers sets entry security' );
    like(
        $entry->event_raw,
        qr/<p>Story notes:<\/p>\npost-war: rebuilding/,
        'HTML message retains post-prefixed body text'
    );
}

{
    my $email_post = DW::EmailPost->get_handler( get_mime( "body-pin", $user_email_info ) );
    my ( $ok, $msg ) = $email_post->process;
    ok( $ok, "posted entry authenticated by a leading body PIN" ) or diag $msg;
    my $entry = LJ::Entry->new( $u, jitemid => 5 );
    is( $entry->security, 'private', 'Header after PIN sets entry security' );
    like( $entry->event_raw, qr/\A\s*A private post\.\z/, 'PIN and header are not published' );
}

{
    my $jitemid  = 5;
    my $preamble = "<!DOCTYPE html>\n<html>\n<head><title>Email title</title></head>\n";

    my $pin_mime = build_message(
        'Body PIN between settings',
        'text/plain',
"post-format: html\n+$emailpin\nlj-format: markdown\npost-security: private\n\nA private post.",
        "$user\@$user_email_info->{POSTDOMAIN}"
    );
    my ( $pin_ok, $pin_msg ) = DW::EmailPost->get_handler($pin_mime)->process;
    ok( $pin_ok, 'Posted an entry authenticated by a body PIN between settings' ) or diag $pin_msg;
    my $pin_entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
    is( $pin_entry->security, 'private', 'Setting after the PIN sets private security' );
    is(
        $pin_entry->prop('editor'),
        DW::Formats::validate('html_casual_latest'),
        'Modern format setting before the PIN takes precedence over legacy format'
    );
    like( $pin_entry->event_raw, qr/\A\s*A private post\.\z/,
        'Settings and PIN are not published' );

    for my $case ( [ 'unclosed', '' ], [ 'closed', "\n-->\npost-icon: unknown" ] ) {
        my ( $label, $closing ) = @$case;
        my $mime = build_message(
            "Setting with a $label HTML comment",
            'text/html',
"post-security: private\npost-format: html <!-- mail note\npost-security: public$closing\n\nMessage"
        );
        my ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
        ok( $ok, "Posted an entry with a $label comment on a setting line" ) or diag $msg;
        my $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
        is( $entry->security, 'private',
            "Security setting inside a $label comment is not applied" );
        is(
            $entry->prop('editor'),
            DW::Formats::validate('html_casual_latest'),
            "Format setting before a $label comment still applies"
        );
    }
    {
        my $mime = build_message(
            'HTML comment before the setting delimiter',
            'text/html',
            "post-security: private\npost-foo <!-- note: x\npost-security: public\n-->\n\nMessage"
        );
        my ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
        ok( $ok, 'Posted an entry with a comment before the setting delimiter' ) or diag $msg;
        my $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
        is( $entry->security, 'private',
            'A colon inside an HTML comment is not a setting delimiter' );
    }
    for my $multipart ( 0, 1 ) {
        my $label   = $multipart ? 'multipart HTML fallback'        : 'HTML-only email';
        my $opening = $multipart ? "<!-- mail client -->\n<body>\n" : '<body>';
        my $message =
              $preamble
            . $opening
            . "post-security: private\n\n<p>A private post.</p>\n</body>\n</html>";
        my $mime = build_message(
            $label,
            $multipart ? 'multipart/mixed' : 'text/html',
            $multipart ? undef             : $message
        );
        if ($multipart) {
            $mime->attach( Type => 'text/html', Data => $message );
            $mime->attach( Type => 'application/octet-stream', Data => 'attachment' );
        }

        my ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
        ok( $ok, "Posted $label" ) or diag $msg;
        my $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
        is( $entry->security, 'private', "Full document in $label uses private security" );
        unlike( $entry->event_raw, qr/post-security:/, "Leading directive removed in $label" );
    }

    my $directive    = "\npost-security: private\n\nMessage";
    my $implied_head = '<!doctype html><title>Mail</title>';
    for my $case (
        [ 'implied body after closed head',  "$preamble$directive</html>" ],
        [ 'implied body with a div wrapper', "$preamble<div>$directive</div></html>" ],
        [ 'implied body after title',        "<head><title>Mail</title>$directive" ],
        [
            'comment immediately inside body',
            "$implied_head<body><!-- mail client -->$directive</body>"
        ],
        [
            'comment before an empty implied head',
            "<!doctype html><!-- generated --><p>$directive</p>"
        ],
        [
            'comments around body wrappers',
"$implied_head<body> <!-- leading --><div><!-- between --><p>$directive</p></div></body>"
        ],
        [
            'implied head and body',
            "$implied_head<p>\npost-secruity: synthetic group$directive</p>"
        ],
        [
            'head with noscript metadata',
            '<head><title>Mail</title><noscript><link rel="stylesheet" href="mail.css">'
                . "<style>p { color: black }</style></noscript></head>$directive"
        ],
        [
            'head with a nested template',
            "$implied_head<template><template><p>Inert content</p></template></template>$directive"
        ],
        )
    {
        my ( $label, $message ) = @$case;
        my $mime = build_message( $label, 'text/html', $message );
        my ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
        ok( $ok, "Posted HTML with $label" ) or diag $msg;
        my $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
        is( $entry->security, 'private', "Leading directive sets private security with $label" );
        unlike(
            $entry->event_raw,
            qr/post-(?:security|secruity):/,
            "Leading directives removed with $label"
        );
    }

    for my $case (
        [ 'explicit body', "$preamble<body>" ],
        [ 'implied body',  $preamble ],
        [ 'implied head',  $implied_head ],
        )
    {
        my ( $label, $opening ) = @$case;
        for my $body_prefix ( '<p>Introductory prose.</p>', '<blockquote>' ) {
            my $closing = $body_prefix eq '<blockquote>' ? "\n</blockquote>" : '';
            my $message =
                "$opening\n$body_prefix\npost-security: private$closing\n</body>\n</html>";
            my $mime = build_message( "HTML with $label and $body_prefix", 'text/html', $message );
            my ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
            ok( $ok, "Posted HTML with $label and $body_prefix" ) or diag $msg;
            my $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
            is( $entry->security, 'public', "No directive applied after $body_prefix in $label" );
            like(
                $entry->event_raw,
                qr/post-security: private/,
                "Text kept after $body_prefix in $label"
            );
        }
    }

    for my $case (
        [ 'standalone comment', '<body>', "<!-- mail client -->\n", '</body>' ],
        [
            'comment and wrapper-only lines',         '<body><div><p>',
            "\n</p>\n  <!-- mail\nclient -->\n<p>\n", '</p></div></body>'
        ],
        )
    {
        my ( $label, $opening, $separator, $closing ) = @$case;
        my $message =
            "$opening\npost-format: html\n${separator}post-security: private\n\nMessage$closing";
        my $mime = build_message( "HTML with $label between settings", 'text/html', $message );
        my ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
        ok( $ok, "Posted HTML with $label between settings" ) or diag $msg;
        my $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
        is( $entry->security, 'private', "Both settings apply across $label" );
        unlike( $entry->event_raw, qr/post-(?:format|security):/,
            "Both settings removed across $label" );
    }

    for my $case (
        [ 'prose', 'text/html', "<!-- mail client -->\n<p>Introductory prose.</p>\n", '' ],
        [ 'blockquote', 'text/html', "<!-- mail client -->\n<blockquote>\n", "\n</blockquote>" ],
        [ 'unclosed comment', 'text/html',  "<!-- mail client\n",     '' ],
        [ 'literal comment',  'text/plain', "<!-- mail client -->\n", '' ],
        )
    {
        my ( $label, $type, $separator, $closing ) = @$case;
        my $message = "post-format: html\n${separator}post-security: private$closing\n\nMessage";
        my $mime    = build_message( "Setting after $label", $type, $message );
        my ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
        ok( $ok, "Posted entry with a setting after $label" ) or diag $msg;
        my $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
        is( $entry->security, 'public', "Setting after $label is not applied" );
        like( $entry->event_raw, qr/post-security: private/, "Text after $label is retained" );
    }

    my $mime = build_message( 'Wrapped security header',
        'text/plain', "post-security:\n  private\n\nA private post." );
    my ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
    ok( $ok, 'Posted entry with a wrapped header' ) or diag $msg;
    my $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
    is( $entry->security,  'private',         'Wrapped header sets private security' );
    is( $entry->event_raw, 'A private post.', 'Wrapped header and continuation are not published' );

    $mime = build_message( 'HTML with an implicit head close',
        'text/html',
        "<!doctype html><html><head><title>Mail</title><body>\npost-security: private\n\nMessage" );
    ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
    ok( $ok, 'Posted HTML with an implicit head close' ) or diag $msg;
    $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
    is( $entry->security, 'private', 'Directive after implicit head close sets private security' );
    unlike( $entry->event_raw, qr/post-security:/,
        'Directive after implicit head close is removed' );

    $mime = build_message(
        'Quote after an empty directive',
        'text/plain',
        "post-icon:\n  > Quoted first line\n\nMessage"
    );
    ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
    ok( $ok, 'Posted a plain-text quote after an empty directive' ) or diag $msg;
    $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
    is( $entry->security, 'public', 'Plain-text quote leaves security at the public default' );
    like( $entry->event_raw, qr/> Quoted first line/, 'The quoted line is retained' );

    $mime = build_message( 'Blockquote after an empty directive',
        'text/html',
        "post-icon:\n  <blockquote>\npost-security: private\n</blockquote>\n\nMessage" );
    ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
    ok( $ok, 'Posted an HTML blockquote after an empty directive' ) or diag $msg;
    $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
    is( $entry->security, 'public', 'Quoted security directive is not applied' );
    like(
        $entry->event_raw,
        qr{<blockquote>\s*post-security: private\s*</blockquote>},
        'The blockquote and quoted directive are retained'
    );

    for my $case (
        [ 'on a setting line', 'post-foo: bar', '<blockquote>', '</blockquote>' ],
        [ 'after a continued value', "post-foo:\n  bar", '<div class="gmail_quote">', '</div>' ],
        )
    {
        my ( $label, $setting, $opening, $closing ) = @$case;
        my $mime = build_message(
            "Quote $label",
            'text/html',
"post-security: private\n$setting$opening\npost-security: public\nQuoted text.\n$closing"
        );
        my ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
        ok( $ok, "Posted an HTML quote $label" ) or diag $msg;
        my $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
        is( $entry->security, 'private', "The private setting still applies $label" );
        like(
            $entry->event_raw,
            qr{\Q$opening\E\s*post-security: public\s+Quoted text\.\s*\Q$closing\E},
            "The quote markup and text are retained $label"
        );
    }

    $mime = build_message(
        'HTML bare setting followed by wrapped privacy setting',
        'text/html',
        "post-format: html\n<p>post-security: private</p>\n<p>Message</p>"
    );
    ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
    ok( $ok, 'Posted HTML with bare setting before wrapped setting' ) or diag $msg;
    $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
    is( $entry->security, 'private', 'Wrapped setting after bare setting still applies' );
    unlike( $entry->event_raw, qr/post-security:/i, 'Wrapped setting line is removed' );

    $mime = build_message(
        'HTML with wrapped and formatted settings',
        'text/html',
        "<p>post-security: private</p>\n"
            . "<p>post-location: <b>Somewhere</b><br>post-format: html</p>\n<p>Message</p>"
    );
    ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
    ok( $ok, 'Posted HTML with wrapped and formatted settings' ) or diag $msg;
    $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
    is( $entry->security, 'private', 'A closing paragraph tag ends the security value' );
    is( $entry->prop('current_location'),
        'Somewhere', 'Inline formatting is not part of the value' );
    is(
        $entry->prop('editor'),
        DW::Formats::validate('html_casual_latest'),
        'A break tag separates settings'
    );

    $mime = build_message(
        'HTML setting with attributed inline formatting before privacy setting',
        'text/html',
        "post-location: <span style=\"font-weight:bold\">Somewhere</span>\n"
            . "post-security: private\n\nMessage"
    );
    ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
    ok( $ok, 'Posted HTML with attributed inline formatting on a setting value' ) or diag $msg;
    $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
    is( $entry->prop('current_location'),
        'Somewhere', 'Attributed inline formatting is stripped from the value' );
    is( $entry->security, 'private', 'Privacy setting after attributed inline tag still applies' );
    unlike(
        $entry->event_raw,
        qr/post-(?:location|security):/i,
        'Settings with attributed inline formatting are removed'
    );

    for my $case (
        [ 'quoted greater-than attribute', 'post-location: <span title="5 > 3">Somewhere</span>', ],
        [ 'quoted less-than attribute',    "post-location: <span title='a < b'>Somewhere</span>", ],
        [
            'multiline opening tag attribute',
            "post-location: <span\nstyle=\"font-weight:bold\">Somewhere</span>",
        ],
        )
    {
        my ( $label, $location_line ) = @$case;
        my $mime = build_message( "HTML setting with $label",
            'text/html', "$location_line\npost-security: private\n\nMessage" );
        my ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
        ok( $ok, "Posted HTML with $label" ) or diag $msg;
        my $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
        is( $entry->prop('current_location'),
            'Somewhere', "Stored location strips inline tag with $label" );
        is( $entry->security, 'private',
            "Privacy setting after inline tag with $label still applies" );
        unlike(
            $entry->event_raw,
            qr/post-(?:location|security):/i,
            "Settings with $label are removed"
        );
    }

    for my $case (
        [
            'break tag', 'post-format: html<br><!-- generated -->post-security: private<br>Message',
        ],
        [ 'explicit body', '<body><!-- generated -->post-security: private<br>Message</body>', ],
        [
            'bare div wrapper',
            '<div><!-- generated -->post-security: private</div><div>Message</div>',
        ],
        )
    {
        my ( $label, $message ) = @$case;
        my $mime = build_message( "Compact HTML comment after $label", 'text/html', $message );
        my ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
        ok( $ok, "Posted compact HTML with comment after $label" ) or diag $msg;
        my $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
        is( $entry->security, 'private',
            "Privacy setting after compact HTML comment ($label) applies" );
        unlike( $entry->event_raw, qr/post-security:/i,
            "Privacy setting after compact HTML comment ($label) is removed" );
        like( $entry->event_raw, qr/Message/,
            "Message body after compact HTML comment ($label) is retained" );
    }

    $mime = build_message(
        'Inline closed comment before trailing text on setting line',
        'text/html',
        "post-security: private\npost-format: html <!-- note -->post-security: public\n\nMessage"
    );
    ( $ok, $msg ) = DW::EmailPost->get_handler($mime)->process;
    ok( $ok, 'Posted HTML with inline closed comment on a setting line' ) or diag $msg;
    $entry = LJ::Entry->new( $u, jitemid => ++$jitemid );
    is( $entry->security, 'private',
        'Trailing setting after same-line inline comment is not applied' );
    like(
        $entry->event_raw,
        qr/post-security: public/,
        'Text after same-line inline comment is retained'
    );
}

sub build_message {
    my ( $subject, $type, $body, $destination ) = @_;
    return MIME::Entity->build(
        From    => $user_email_info->{FROM_EMAIL},
        To      => $destination // "$user+$emailpin\@$user_email_info->{POSTDOMAIN}",
        Date    => 'Mon, 1 Jan 2007 12:28:00 -0800',
        Subject => $subject,
        Type    => $type,
        ( defined($body) ? ( Data => $body ) : () ),
    );
}

sub get_mime {
    my ( $filepart, $replace ) = @_;
    $replace ||= {};

    my $file   = "$Bin/data/emailpost/$filepart.txt";
    my $tmpdir = File::Temp::tempdir( CLEANUP => 1 );
    open( my $fh, $file )
        or die "Couldn't open file $file: $!";
    my $outfile = "$tmpdir/email-with-substs-$filepart";
    open( my $newfh, "+>$outfile" )
        or die "Couldn't open file $outfile for writing: $!";
    while (<$fh>) {
        s/\$\{(.+?)\}/$replace->{$1} || die "Unknown substitution: $1"/eg;
        print $newfh $_;
    }
    seek( $newfh, 0, 0 );    # seek to beginning

    my $parser = MIME::Parser->new;
    $parser->output_dir($tmpdir);

    my $entity;
    return eval { $entity = $parser->parse($newfh); };
}

1;
