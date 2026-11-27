# t/plack-talkscreen.t
#
# Comment moderation confirmation and return links through /talkscreen.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'talkscreenTest';

my $owner  = temp_user();
my $author = temp_user();
$_->update_self( { status => 'A' } ) for ( $owner, $author );

my $entry       = $owner->t_post_fake_entry;
my $comment     = $entry->t_enter_comment( u => $author );
my $journal     = $owner->user;
my $talkid      = $comment->dtalkid;
my $endpoint    = 'http://localhost/talkscreen';
my $entry_url   = LJ::ehtml( $entry->url );
my $comment_url = LJ::ehtml( $comment->url );
my $prompt_url  = LJ::ehtml( $entry->url( view => $talkid, anchor => "cmt$talkid" ) );

my $state = sub {
    return LJ::get_cluster_master($owner)
        ->selectrow_array( 'SELECT state FROM talk2 WHERE journalid = ? AND jtalkid = ?',
        undef, $owner->id, $comment->jtalkid );
};

with_fake_memcache {
    test_psgi $app, sub {
        my $request = shift;

        my $submit = sub {
            my ( $viewer, $mode, $id, $token ) = @_;
            return $request->(
                POST "$endpoint?as=" . $viewer->user,
                Content => [
                    mode         => $mode,
                    journal      => $journal,
                    talkid       => $id,
                    confirm      => 'Y',
                    lj_form_auth => $token,
                ],
            );
        };

        LJ::set_remote($author);
        delete $LJ::REQ_GLOBAL{form_auth_chal};
        my $author_token = LJ::form_auth(1);
        LJ::set_remote(undef);

        my $denied = $submit->( $author, 'screen', $talkid, $author_token );
        like( $denied->content, qr/permission to screen/, 'comment author cannot screen it' );
        unlike( $denied->content, qr/\Q$comment_url\E/, 'denial does not show a return link' );
        is( $state->(), 'A', 'denied POST leaves the comment active' );

        my $owner_token;
        for my $action ( [ screen => 'S' ], [ unscreen => 'A' ], [ freeze => 'F' ],
            [ unfreeze => 'A' ] )
        {
            my ( $mode, $expected_state ) = @$action;
            my $before = $state->();
            my $form   = $request->(
                GET "$endpoint?as=$journal&mode=$mode&journal=$journal&talkid=$talkid" );
            is( $form->code, 200, "$mode confirmation prompt renders" );
            like(
                $form->content,
                qr{<a\b[^>]*\bhref=['"]\Q$prompt_url\E['"]},
                "$mode prompt links to the comment in the entry"
            );
            is( $state->(), $before, "$mode GET does not change comment state" );

            ($owner_token) = $form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
            ok( $owner_token, "$mode prompt supplies a form token" );
            my $success = $submit->( $owner, $mode, $talkid, $owner_token );
            is( $success->code, 200,             "$mode confirmation response renders" );
            is( $state->(),     $expected_state, "$mode POST changes comment state" );
            like(
                $success->content,
                qr{<a\b[^>]*\bhref=['"]\Q$entry_url\E['"]},
                "$mode confirmation keeps the entry link"
            );
            like(
                $success->content,
                qr{<a\b[^>]*\bhref=['"]\Q$comment_url\E['"]},
                "$mode confirmation links directly to the comment"
            );
        }

        my $missing = $submit->( $owner, 'screen', $talkid + 256, $owner_token );
        like( $missing->content, qr/This comment doesn.*?t exist/, 'missing comment is rejected' );

        $comment->delete;
        my $deleted = $submit->( $owner, 'screen', $talkid, $owner_token );
        like( $deleted->content, qr/comment has been deleted/, 'deleted comment is rejected' );
        unlike( $deleted->content, qr/\Q$comment_url\E/, 'deleted comment has no return link' );
        is( $state->(), 'D', 'deleted comment stays deleted' );
    };
};

done_testing();
