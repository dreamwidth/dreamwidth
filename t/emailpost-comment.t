# t/emailpost-comment.t
#
# Test replying to comments via email.
#
# Authors:
#      Afuna <coder.dw@afunamatata.com>
#
# Copyright (c) 2013 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use FindBin qw($Bin);

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::EmailPost::Comment;
use LJ::Emailpost::Web;
use LJ::Test;
use LJ::Userpic;
use MIME::Entity;

my $subject;
my $u = temp_user();

my $e = $u->t_post_fake_entry;

my $username  = $u->display_name;
my $ditemid   = $e->ditemid;
my $generated = " [ $username - $ditemid ]";

my $c_parent = $e->t_enter_comment;
my $c1       = $e->t_enter_comment( parent => $c_parent );

#   email subject       parent comment subject
#    generated                  none                 - none
#    generated                  custom               - Re: custom parent
#    custom                     none                 - custom from email
#    custom                     custom               - custom from email

$c_parent->set_subject("");
$subject = DW::EmailPost::Comment->determine_subject( "Re: Reply to an entry. $generated",
    $u, $ditemid, $c_parent->dtalkid );
is( $subject, "", "default parent subject, default email subject" );

$c_parent->set_subject("Some custom subject");
$subject = DW::EmailPost::Comment->determine_subject( "Re: Some custom subject $generated",
    $u, $ditemid, $c_parent->dtalkid );
is( $subject, "Re: Some custom subject", "custom parent subject, default email subject" );

$c_parent->set_subject("Make sure punctuation isn't escaped");
$subject =
    DW::EmailPost::Comment->determine_subject( "Re: Make sure punctuation isn't escaped $generated",
    $u, $ditemid, $c_parent->dtalkid );
is(
    $subject,
    "Re: Make sure punctuation isn't escaped",
    "punctuated parent subject, default email subject"
);

$c_parent->set_subject("");
$subject = DW::EmailPost::Comment->determine_subject( "Change of topic mid-thread",
    $u, $ditemid, $c_parent->dtalkid );
is( $subject, "Change of topic mid-thread", "default parent subject, custom email subject" );

$c_parent->set_subject("Some custom subject");
$subject = DW::EmailPost::Comment->determine_subject( "Change of topic mid-thread",
    $u, $ditemid, $c_parent->dtalkid );
is( $subject, "Change of topic mid-thread", "custom parent subject, custom email subject" );

$subject = DW::EmailPost::Comment->determine_subject( "Make sure punctuation isn't escaped",
    $u, $ditemid, $c_parent->dtalkid );
is(
    $subject,
    "Make sure punctuation isn't escaped",
    "custom parent subject, punctuated email subject"
);

subtest 'Email replies and CAPTCHA' => sub {
    local $LJ::T_ALLOW_EMAILPOST        = 1;
    local $LJ::EMAIL_REPLY_DOMAIN       = 'reply.example.com';
    local $LJ::DISABLED{captcha}        = 0;
    local %LJ::CAPTCHA_FOR              = ( comment_html_auth => 1 );
    local $LJ::CAPTCHA_HCAPTCHA_SITEKEY = 'test-sitekey';
    local $LJ::CAPTCHA_HCAPTCHA_SECRET  = 'test-secret';

    my $owner     = temp_user();
    my $commenter = temp_user();
    $commenter->update_self( { status          => 'A' } );
    $owner->update_self(     { opt_whocanreply => 'all' } );

    my $entry  = $owner->t_post_fake_entry;
    my $parent = $entry->t_enter_comment( u => $owner );
    my $from   = $commenter->user . '@example.com';
    my $to     = DW::EmailPost::Comment->replyto_address( $commenter, $owner,
        $entry->ditemid, $parent->dtalkid );
    LJ::Emailpost::Web::set_allowed_senders( $commenter, { $from => { get_errors => 1 } } );

    my @bounces;
    no warnings qw(redefine once);
    local *LJ::send_mail = sub { push @bounces, $_[0]; return 1; };

    my $reply = sub {
        my ($text) = @_;
        @bounces = ();
        my $mime = MIME::Entity->build(
            From    => $from,
            To      => $to,
            Subject => 'A comment reply',
            Type    => 'text/plain',
            Data    => "$text\n",
        );
        my $ok;
        with_fake_memcache { ($ok) = DW::EmailPost::Comment->new($mime)->process; };
        return $ok;
    };

    my $text = 'Here is my reply to the discussion.';
    my $url  = $parent->reply_url;
    $owner->set_prop( opt_show_captcha_to => 'A' );
    ok( !$reply->($text), 'email cannot post a reply when the journal requires a CAPTCHA' );
    is( scalar @bounces, 1, 'one bounce was sent' );
    like( $bounces[0]{body}, qr/CAPTCHA.*required/i, 'bounce explains the CAPTCHA requirement' );
    like( $bounces[0]{body}, qr/\Q$url\E/,  'bounce links to the reply form for the parent' );
    like( $bounces[0]{body}, qr/\Q$text\E/, 'bounce includes the attempted reply text' );

    $owner->set_prop( opt_show_captcha_to => 'N' );
    ok(
        !$reply->('Compare http://first.example with http://second.example'),
        'email still rejects a reply flagged by the content anti-spam check'
    );
    is( scalar @bounces, 1, 'anti-spam rejection sent one bounce' );
    like(
        $bounces[0]{body},
        qr/Message looks like spam/,
        'anti-spam bounce retains the spam error'
    );

    ok( $reply->($text), 'ordinary reply posts successfully without the CAPTCHA requirement' );
    is( scalar @bounces, 0, 'successful reply did not send a bounce' );
    my @replies = grep { $_->parenttalkid == $parent->jtalkid } $entry->comment_list;
    is( scalar @replies, 1, 'only the successful reply was stored under the parent' );
    like( $replies[0] && $replies[0]->body_raw,
        qr/\A\Q$text\E\s*\z/, 'stored reply has the email text' );
};

subtest 'email replies can choose a random icon' => sub {
    local $LJ::T_ALLOW_EMAILPOST  = 1;
    local $LJ::EMAIL_REPLY_DOMAIN = 'reply.example.com';

    my $commenter = temp_user();
    $commenter->update_self( { status => 'A' } );
    my $from = $commenter->user . '@example.com';
    LJ::Emailpost::Web::set_allowed_senders( $commenter, { $from => { get_errors => 1 } } );

    open( my $image, '<:raw', "$Bin/data/userpics/good.png" ) or die "Open icon fixture: $!";
    my $data = do { local $/; <$image> };
    my $icon = LJ::Userpic->create( $commenter, data => \$data ) or die 'Create icon fixture';

    my $check_reply = sub {
        my ( $header, $expected ) = @_;
        my $entry  = $u->t_post_fake_entry;
        my $parent = $entry->t_enter_comment( u => $u );
        my $to     = DW::EmailPost::Comment->replyto_address( $commenter, $u,
            $entry->ditemid, $parent->dtalkid );
        my $mime = MIME::Entity->build(
            From    => $from,
            To      => $to,
            Subject => 'A comment reply',
            Type    => 'text/plain',
            Data    => "$header\n\nHere is my reply to the discussion.\n",
        );
        my ( $ok, $message );
        with_fake_memcache { ( $ok, $message ) = DW::EmailPost::Comment->new($mime)->process; };
        ok( $ok, "reply with $header posts" ) or return diag $message;
        my ($reply) = grep { $_->parenttalkid == $parent->jtalkid } $entry->comment_list;
        is( $reply && $reply->userpic_kw, $expected,
            "reply with $header stores the selected icon" );
        my $selected = $reply && $reply->userpic;
        is( $selected && $selected->id, $icon->id, 'the stored selection resolves to the icon' );
    };

    $check_reply->( 'post-icon: random', 'pic#' . $icon->id );
    $icon->set_keywords('favorite');
    $check_reply->( 'post-userpic: RANDOM', 'favorite' );
};

done_testing();
