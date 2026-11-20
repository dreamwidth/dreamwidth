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

use Test::More tests => 11;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::EmailPost::Comment;
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

{
    local $LJ::T_ALLOW_EMAILPOST  = 1;
    local $LJ::EMAIL_REPLY_DOMAIN = 'reply.example.com';
    $u->update_self( { status => 'A' } );
    DW::EmailPost::Comment::generate_auth($u);

    open my $image, '<:raw', "$ENV{LJHOME}/t/data/userpics/good.png" or die $!;
    my $data = do { local $/; <$image> };
    my $icon = LJ::Userpic->create( $u, data => \$data );
    $icon->set_keywords('reply icon');

    my $body = <<'BODY';
post-icon: reply icon
post-format: html

Here are my notes:
post-icon: part of the message
post-format: markdown
BODY
    my $mime = MIME::Entity->build(
        From    => $u->email_raw,
        To      => DW::EmailPost::Comment->replyto_address( $u, $u, $ditemid, $c_parent->dtalkid ),
        Subject => 'Email reply with settings',
        Type    => 'text/plain',
        Data    => $body,
    );
    my ( $ok, $msg ) = DW::EmailPost::Comment->new($mime)->process;
    ok( $ok, 'Posted an email reply with settings' ) or diag $msg;

    my $entry = LJ::Entry->new( $u, ditemid => $ditemid );
    my ($reply) = grep { $_->subject_raw eq 'Email reply with settings' } $entry->comment_list;
    ok( $reply, 'Reply saved on the entry' );
SKIP: {
        skip 'No reply was saved', 3 unless $reply;
        is( $reply->userpic_kw, 'reply icon', 'Leading post-icon sets the reply icon' );
        is(
            $reply->prop('editor'),
            DW::Formats::validate('html_casual_latest'),
            'Leading post-format sets the reply editor'
        );
        like(
            $reply->body_raw,
            qr/\AHere are my notes:\npost-icon: part of the message\npost-format: markdown\s*\z/,
            'Settings-like lines after reply prose are published unchanged'
        );
    }
}
