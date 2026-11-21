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

use Test::More tests => 98;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::EmailPost;
use LJ::Emailpost::Web;
use LJ::Protocol;
use LJ::Userpic;

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
    is(
        $entry->eventtime_mysql,
        "2007-01-01 12:28:00",
        "without a timezone set, entry uses the Date header's local time"
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
    $u->set_prop( timezone => 'America/New_York' );
    my $email_post = DW::EmailPost->get_handler( get_mime( "timezone", $user_email_info ) );
    my ( $ok, $msg ) = $email_post->process;
    ok( $ok, "posted entry with a user timezone set" );
    my $entry = LJ::Entry->new( $u, jitemid => 4 );
    is( $entry->subject_raw, "Emailed from a UTC mail client", "got the timezone entry" );
    is(
        $entry->eventtime_mysql,
        "2007-07-01 02:00:00",
        "entry time is converted from the Date header into the user's timezone"
    );
    $u->set_prop( timezone => undef );
}

{
    my $email_post = DW::EmailPost->get_handler( get_mime( "html-headers", $user_email_info ) );
    my ( $ok, $msg ) = $email_post->process;
    ok( $ok, "posted HTML entry with custom settings" ) or diag $msg;
    my $entry = LJ::Entry->new( $u, jitemid => 5 );
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
    my $entry = LJ::Entry->new( $u, jitemid => 6 );
    is( $entry->security, 'private', 'Header after PIN sets entry security' );
    like( $entry->event_raw, qr/\A\s*A private post\.\z/, 'PIN and header are not published' );
}

{
    my $jitemid  = 6;
    my $preamble = "<!DOCTYPE html>\n<html>\n<head><title>Email title</title></head>\n";
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
}

sub build_message {
    my ( $subject, $type, $body ) = @_;
    return MIME::Entity->build(
        From    => $user_email_info->{FROM_EMAIL},
        To      => "$user+$emailpin\@$user_email_info->{POSTDOMAIN}",
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

my $post_count = 0;

sub email_entry {
    my ( $poster, $journal, $pin, @headers ) = @_;
    LJ::start_request();
    my $destination = $poster->user;
    $destination .= '.' . $journal->user unless $poster->equals($journal);
    my $body = 'Testing email headers ' . ++$post_count;
    my $mime = MIME::Entity->build(
        From    => $user_email_info->{FROM_EMAIL},
        To      => "$destination+$pin\@$user_email_info->{POSTDOMAIN}",
        Date    => 'Mon, 1 Jan 2007 12:30:00 -0800',
        Subject => $body,
        Data    => join( "\n", @headers, '', $body, '' ),
    );
    my ( $posted, $message ) = DW::EmailPost->get_handler($mime)->process;
    return ( undef, $message ) unless $posted;

    my $itemid = $journal->selectrow_array( 'SELECT MAX(jitemid) FROM log2 WHERE journalid = ?',
        undef, $journal->id );
    my $entry = $itemid && LJ::Entry->new( $journal, jitemid => $itemid );
    return ( $entry, $message );
}

sub add_icon {
    my ( $owner, $file, $keywords ) = @_;
    open( my $image, '<:raw', "$Bin/data/userpics/$file" ) or die "Open $file: $!";
    my $data = do { local $/; <$image> };
    my $icon = LJ::Userpic->create( $owner, data => \$data ) or die "Create icon: $file";
    $icon->set_keywords($keywords) if defined $keywords;
    return $icon;
}

subtest 'email slug normalization and aliases' => sub {
    my ( $slugged, $message ) =
        email_entry( $u, $u, $emailpin, 'lj-slug: ignored', 'Post-Slug: Paris -- Trip!' );
    ok( $slugged && $slugged->valid, 'posted with a slug' ) or diag $message;
    is( $slugged && $slugged->slug, 'paris-trip', 'post-slug overrides and normalizes lj-slug' );
    like( $slugged && $slugged->url, qr{/paris-trip\.html$}, 'permalink uses the normalized slug' );
    like(
        $slugged && $slugged->event_raw,
        qr/^Testing email headers \d+$/,
        'no slug header is left in the entry body'
    );

    my ($legacy) = email_entry( $u, $u, $emailpin, 'lj-slug: Old Style' );
    is( $legacy && $legacy->slug, 'old-style', 'lj-slug works on its own' );

    my ($plain) = email_entry( $u, $u, $emailpin, 'post-mood: happy' );
    is( $plain && $plain->slug, '', 'omitting the slug still gives a numeric permalink' );
};

subtest 'invalid and duplicate slugs fall back to numeric permalinks' => sub {
    my ($first) = email_entry( $u, $u, $emailpin, 'post-slug: Unique Name' );
    is( $first && $first->slug, 'unique-name', 'first entry claims the slug' );

    my ($duplicate) = email_entry( $u, $u, $emailpin, 'post-slug: UNIQUE--NAME' );
    ok( $duplicate && $duplicate->valid, 'duplicate slug does not prevent posting' );
    is( $duplicate && $duplicate->slug, '', 'duplicate has no slug' );
    like( $duplicate && $duplicate->url, qr{/\d+\.html$}, 'duplicate uses its numeric permalink' );
    my $lookup = LJ::Entry->new( $u, slug => 'unique-name' );
    is(
        $lookup && $lookup->jitemid,
        $first  && $first->jitemid,
        'slug still resolves to first entry'
    );

    my ($invalid) = email_entry( $u, $u, $emailpin, 'post-slug: ..?!' );
    ok( $invalid && $invalid->valid, 'a slug that normalizes to empty does not prevent posting' );
    is( $invalid && $invalid->slug, '', 'invalid slug is not saved' );
    my ($numeric) = email_entry( $u, $u, $emailpin, 'post-slug: 1234' );
    is( $numeric && $numeric->slug, '1234', 'numeric slugs are accepted' );
};

subtest 'a zero email slug round-trips through its dated permalink' => sub {
    my ( $entry, $message ) = email_entry( $u, $u, $emailpin, 'post-slug: 0' );
    ok( $entry && $entry->valid, 'the entry posts' ) or return diag $message;

    my $journalid = $u->id;
    my $itemid    = $entry->jitemid;
    LJ::MemCache::delete( [ $journalid, "logslug:$journalid:$itemid" ] );
    LJ::start_request();
    my $reloaded = LJ::Entry->new( $u, jitemid => $itemid );
    is( $reloaded->slug, '0', 'the uncached entry still has the zero slug' );
    like( $reloaded->url, qr{/\d{4}/\d{2}/\d{2}/0\.html$}, 'permalink uses the dated zero slug' );
    my $lookup = LJ::Entry->new( $u, slug => '0' );
    is( $lookup && $lookup->jitemid, $itemid, 'the zero slug resolves to the entry' );
};

subtest 'a truncated email slug round-trips through its permalink' => sub {
    my $prefix = 'a' x 99;
    my ($entry) = email_entry( $u, $u, $emailpin, "post-slug: $prefix-b" );
    ok( $entry && $entry->valid, 'the entry posts' ) or return;
    is( $entry->slug, $prefix, 'a hyphen at the truncation boundary is dropped' );
    my ($permalink) = $entry->url =~ m{/([^/]+)\.html$};
    is( $permalink, $prefix, 'the permalink uses the same slug' );
    my $lookup = LJ::Entry->new( $u, slug => $permalink );
    is( $lookup && $lookup->jitemid, $entry->jitemid, 'the permalink resolves to the entry' );
};

subtest 'random icon uses selectable keywords without changing explicit keywords' => sub {
    my ($no_icon) = email_entry( $u, $u, $emailpin, 'post-icon: random' );
    ok( $no_icon && !$no_icon->userpic, 'random works with no icons' );

    add_icon( $u, 'good.png', 'alpha' );
    my ($only_icon) = email_entry( $u, $u, $emailpin, 'lj-userpic: RANDOM' );
    is( $only_icon && $only_icon->userpic_kw, 'alpha', 'random can select the only icon' );

    add_icon( $u, 'good.jpg', 'beta, gamma' );
    my %selectable = map { $_ => 1 } qw(alpha beta gamma);
    my %picked;
    srand(2314);
    foreach ( 1 .. 16 ) {
        my ($random) = email_entry( $u, $u, $emailpin, 'post-icon: random' );
        $picked{ ( $random && $random->userpic_kw ) // '' }++;
    }
    is_deeply( [ grep { !$selectable{$_} } sort keys %picked ],
        [], 'each random selection is a valid keyword, never the default option' );
    cmp_ok( scalar keys %picked, '>', 1, 'random selections can vary between entries' );

    $u->set_prop( emailpost_userpic => 'gamma' );
    my ($default) = email_entry( $u, $u, $emailpin, 'post-mood: happy' );
    is( $default && $default->userpic_kw, 'gamma', 'omitted header uses email posting default' );
    my ($named) = email_entry( $u, $u, $emailpin, 'post-icon: random', 'post-userpic: beta' );
    is( $named && $named->userpic_kw, 'beta', 'explicit userpic wins over the icon alias' );

    add_icon( $u, 'good.gif', 'random' );
    my ($literal) = email_entry( $u, $u, $emailpin, 'post-icon: random' );
    is( $literal && $literal->userpic_kw, 'random', 'existing keyword named random still works' );
};

subtest 'new headers still respect PIN, journal permissions, and privacy' => sub {
    my $community = temp_comm();
    $u->update_self( { status => 'A' } );
    my @headers = ( 'post-slug: Unique Name', 'post-icon: RANDOM', 'post-security: access' );
    my ( $denied, $denial ) = email_entry( $u, $community, 'wrongpin', @headers );
    ok( !$denied, 'headers do not bypass the email PIN' );
    like( $denial, qr/Invalid PIN/, 'posting first checks the PIN' );

    ( $denied, $denial ) = email_entry( $u, $community, $emailpin, @headers );
    ok( !$denied, 'headers do not grant permission to post to a community' );
    like( $denial, qr/access|permission/i, 'posting reports an authorization error' );
    ok( !LJ::Entry->new( $community, slug => 'unique-name' ),
        'rejected posts do not claim the slug' );

    LJ::set_rel( $community, $u, 'P' );
    my ( $posted, $message ) = email_entry( $u, $community, $emailpin, @headers );
    ok( $posted && $posted->valid, 'authorized community post succeeds' ) or diag $message;
    is( $posted && $posted->slug, 'unique-name', 'slug uniqueness is scoped to the journal' );
    ok( $posted && $posted->poster->equals($u), 'sender is the community entry author' );
    like(
        $posted && $posted->userpic_kw,
        qr/\A(?:alpha|beta|gamma|random)\z/,
        'random keyword comes from the sender rather than the community'
    );
    ok( $posted && $posted->userpic && $posted->userpic->userid == $u->id,
        "community entry uses the sender's icon" );
    is( $posted && $posted->security,  'usemask', 'entry remains access-only' );
    is( $posted && $posted->allowmask, 1,         'entry uses the community access list' );
};

subtest 'random icon includes keywordless active icons and excludes inactive icons' => sub {
    my $sender = temp_user();
    LJ::Emailpost::Web::set_allowed_senders( $sender,
        { $user_email_info->{FROM_EMAIL} => { get_errors => 1 } } );
    $sender->set_prop( emailpost_pin => $emailpin );
    my $unkeyworded = add_icon( $sender, 'good.png' );
    my $inactive    = add_icon( $sender, 'good.jpg', 'inactive' );
    $sender->do( q{UPDATE userpic2 SET state = 'I' WHERE userid = ? AND picid = ?},
        undef, $sender->id, $inactive->id );
    LJ::Userpic->delete_cache($sender);
    is( scalar $unkeyworded->keywords( raw => 1 ), '', 'active icon has no real keyword' );
    ok( LJ::Userpic->new( $sender, $inactive->id )->inactive, 'named icon is inactive' );

    my ( $keywordless, $message ) = email_entry( $sender, $sender, $emailpin, 'post-icon: random' );
    ok( $keywordless && $keywordless->valid, 'the entry posts with a keywordless icon available' )
        or do { diag $message; return };
    is(
        $keywordless->userpic_kw,
        'pic#' . $unkeyworded->id,
        'stores a selection for the only active icon, even though it has no keyword'
    );
    my $icon = $keywordless->userpic;
    is( $icon && $icon->id, $unkeyworded->id, 'the stored selection resolves to that icon' );

    $unkeyworded->set_keywords('pic#favorite');
    my ($selected) = email_entry( $sender, $sender, $emailpin, 'post-icon: RANDOM' );
    is( $selected && $selected->userpic_kw, 'pic#favorite', 'a literal pic# keyword is eligible' );

    $unkeyworded->set_keywords('Random');
    add_icon( $sender, 'good.gif', 'another' );
    srand(2314);
    foreach ( 1 .. 4 ) {
        my ($explicit) = email_entry( $sender, $sender, $emailpin, 'post-icon: Random' );
        is( $explicit && $explicit->userpic_kw, 'Random', 'exact mixed-case keyword still works' );
    }
};

subtest 'community slug changes use the community writer' => sub {
    my $community = temp_comm();
    LJ::set_rel( $community, $u, 'P' );

    my @writes;
    my $user_do = \&LJ::User::do;
    no warnings 'redefine';
    local *LJ::User::do = sub {
        my ( $writer, $sql ) = @_;
        push @writes, [ uc $1, $writer->id ] if $sql =~ /\A(INSERT|DELETE)\b.*\blogslugs\b/i;
        return $user_do->(@_);
    };

    my ( $entry, $message ) =
        email_entry( $u, $community, $emailpin, 'post-slug: Community First' );
    ok( $entry && $entry->valid, 'community entry posts' ) or do { diag $message; return };
    is( $entry->slug, 'community-first', 'community slug is stored' );
    is_deeply( \@writes, [ [ INSERT => $community->id ] ], 'creation uses the community writer' );

    my $edit_slug = sub {
        my ($slug) = @_;
        @writes = ();
        LJ::start_request();
        my $error  = 0;
        my $result = LJ::Protocol::do_request(
            'editevent',
            {
                username   => $u->user,
                usejournal => $community->user,
                ver        => $LJ::PROTOCOL_VER,
                itemid     => $entry->jitemid,
                event      => 'Updated community entry',
                slug       => $slug,
            },
            \$error,
            { noauth => 1 }
        );
        ok( $result && !$error, 'community edit succeeds' )
            or diag LJ::Protocol::error_message($error);
        return LJ::Entry->new( $community, jitemid => $entry->jitemid )->slug;
    };

    is( $edit_slug->('Community Second'), 'community-second', 'slug is replaced' );
    is_deeply(
        \@writes,
        [ [ DELETE => $community->id ], [ INSERT => $community->id ] ],
        'replacement uses the community writer for both writes'
    );
    ok( !LJ::Entry->new( $community, slug => 'community-first' ), 'old slug no longer resolves' );

    is( $edit_slug->(''), '', 'slug is cleared' );
    is_deeply( \@writes, [ [ DELETE => $community->id ] ], 'removal uses the community writer' );
    ok( !LJ::Entry->new( $community, slug => 'community-second' ),
        'removed slug no longer resolves' );
};

1;
