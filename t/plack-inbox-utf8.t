#!/usr/bin/perl
# t/plack-inbox-utf8.t
#
# Tests UTF-8 text in comment notifications on the inbox response paths.
#
# Authors:
#      Dreamwidth contributors
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use utf8;

use Encode qw(encode_utf8);
use HTTP::Request::Common;
use JSON::PP qw(decode_json encode_json);
use Plack::Test;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Event::JournalNewComment;
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'inboxUtf8Test';

my $owner  = temp_user();
my $author = temp_user();
$_->update_self( { status => 'A' } ) for ( $owner, $author );

my $entry_subject   = 'Запись в журнале';
my $comment_subject = 'Тема комментария';
my $comment_body    = 'Привет из комментария!';
my $comment_title   = 'Привет &#x416;';
my $expected_title  = 'Привет Ж';

my $entry   = $owner->t_post_fake_entry( subject => encode_utf8($entry_subject) );
my $comment = $entry->t_enter_comment(
    u       => $author,
    subject => encode_utf8($comment_subject),
    body    => encode_utf8(qq{<span title="$comment_title">$comment_body</span>}),
);
my $inbox = $owner->notification_inbox;
my $event = LJ::Event::JournalNewComment->new($comment);
my $item  = $inbox->enqueue( event => $event );
my $other = $inbox->enqueue( event => $event );

test_psgi $app, sub {
    my $request = shift;
    my $as      = $owner->user;

    for my $path ( '/inbox/', '/inbox/new' ) {
        my $response =
            $request->( GET "http://localhost$path?as=$as&view=all&expand=" . $item->qid );
        is( $response->code, 200, "$path renders" );
        like( $response->header('Content-Type'), qr/charset=utf-8/i, "$path declares UTF-8" );
        for my $text ( $entry_subject, $comment_subject, $comment_body ) {
            like(
                $response->content,
                qr/\Q@{[encode_utf8($text)]}\E/,
                "$path preserves notification text"
            );
        }
        my ($title) =
            $response->content =~ /<span title="([^"]*)">\Q@{[encode_utf8($comment_body)]}\E/;
        is(
            $title,
            encode_utf8($expected_title),
            "$path preserves Cyrillic next to an HTML entity"
        );
    }

    LJ::set_remote($owner);
    delete $LJ::REQ_GLOBAL{form_auth_chal};
    my $token = LJ::form_auth(1);
    LJ::set_remote(undef);

    my $response = $request->(
        POST "http://localhost/__rpc_inbox_actions?as=$as",
        Content_Type => 'application/json',
        Content =>
            encode_json( { action => 'delete', ids => [ $other->qid ], lj_form_auth => $token } ),
    );
    is( $response->code, 200, 'beta inbox redraw responds' );
    my $result = decode_json( $response->content );

    for my $text ( $entry_subject, $comment_subject, $comment_body ) {
        like( $result->{success}{items},
            qr/\Q$text\E/, 'beta inbox redraw preserves notification text' );
    }
    my ($title) = $result->{success}{items} =~ /<span title="([^"]*)">\Q$comment_body\E/;
    is( $title, $expected_title, 'beta inbox redraw preserves Cyrillic next to an HTML entity' );
};

done_testing;
