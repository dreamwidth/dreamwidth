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
use JSON qw(decode_json);
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm with_fake_memcache);

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

subtest 'Screening and freezing are independent' => sub {
    my $owner     = temp_user();
    my $commenter = temp_user();
    my $stranger  = temp_user();
    my $manager   = temp_user();
    my $community = temp_comm();
    LJ::set_rel( $community, $manager, 'A' );
    $_->update_self( { status => 'A' } ) for ( $owner, $stranger );

    my $personal_entry  = $owner->t_post_fake_entry;
    my $community_entry = $owner->t_post_fake_entry(
        usejournal      => $community->user,
        usejournal_okay => 1
    );

    my $moderation_state = sub {
        my ( $comment, $screened, $frozen, $description ) = @_;
        my ( $journal, $jtalkid ) = ( $comment->journal, $comment->jtalkid );
        LJ::Comment->reset_singletons;
        my $fresh = LJ::Comment->new( $journal, jtalkid => $jtalkid );
        is( $fresh->is_screened, $screened, "$description: screening persists" );
        is( $fresh->is_frozen,   $frozen,   "$description: freezing persists" );
        is( !!$fresh->visible_to($stranger), !!( !$screened ),
            "$description: stranger visibility" );
    };

    with_fake_memcache {
        my $root      = $personal_entry->t_enter_comment( u => $commenter, state => 'S' );
        my $child     = $root->t_reply( u => $commenter );
        my $sibling   = $personal_entry->t_enter_comment( u => $commenter );
        my $comm_root = $community_entry->t_enter_comment( u => $commenter, state => 'S' );

        test_psgi $app, sub {
            my ($request) = @_;
            my $form_auth = sub {
                my ($actor) = @_;
                LJ::set_remote($actor);
                delete $LJ::REQ_GLOBAL{form_auth_chal};
                my $auth = LJ::form_auth(1);
                LJ::set_remote(undef);
                return $auth;
            };

            my $moderate = sub {
                my ( $actor, $comment, $mode, $ajax ) = @_;
                my $endpoint   = $ajax ? '__rpc_talkscreen?jsmode=1&json=1&' : 'talkscreen?';
                my $actor_name = $actor->user;
                my $response   = $request->(
                    POST "http://localhost/${endpoint}as=$actor_name",
                    Content => [
                        mode         => $mode,
                        journal      => $comment->journal->user,
                        talkid       => $comment->dtalkid,
                        confirm      => 'Y',
                        lj_form_auth => $form_auth->($actor),
                    ],
                );

                if ($ajax) {
                    is( $response->code, 200, "AJAX $mode returns a response" );
                    return decode_json( $response->content );
                }
                return $response->content;
            };

            my $owner_name = $owner->user;
            my $recent =
                sub { $request->( GET "http://localhost/comments/recent?as=$owner_name" ) };
            my $root_dtalkid = $root->dtalkid;
            my $reply_link   = qr/href='[^']*\breplyto=$root_dtalkid\b/;
            my $post_reply   = sub {
                my ( $actor, %extra ) = @_;
                my $actor_name = $actor->user;
                return $request->(
                    POST "http://localhost/talkpost_do?as=$actor_name",
                    Content => [
                        lj_form_auth => $form_auth->($actor),
                        chrp1        => LJ::Talk::generate_chrp1(
                            $personal_entry->journalid,
                            $personal_entry->ditemid
                        ),
                        journal      => $owner_name,
                        itemid       => $personal_entry->ditemid,
                        parenttalkid => $root->jtalkid,
                        usertype     => 'cookieuser',
                        cookieuser   => $actor_name,
                        body         => 'A reply to the screened root',
                        %extra,
                    ],
                );
            };
            my $child_count = sub {
                my $talkdata = LJ::Talk::get_talk_data( $owner, 'L', $personal_entry->jitemid );
                return scalar grep { $_->{parenttalkid} == $root->jtalkid } values %$talkdata;
            };

            like( $moderate->( $commenter, $root, 'freeze', 1 )->{error},
                qr/permission/i, 'a comment author cannot freeze their own screened comment' );
            ok(
                $moderate->( $stranger, $root, 'freeze', 1 )->{error},
                'a stranger cannot moderate a screened comment'
            );
            $moderation_state->( $root, 1, 0, 'unauthorized freeze' );
            like( $recent->()->content,
                $reply_link, 'Recent Comments offers a reply before freezing' );

            like( $moderate->( $owner, $root, 'freeze', 1 )->{newurl},
                qr/mode=unfreeze/, 'AJAX freeze offers the inverse action' );
            $moderation_state->( $root,    1, 1, 'screened thread root after AJAX freeze' );
            $moderation_state->( $child,   0, 1, 'public descendant after AJAX freeze' );
            $moderation_state->( $sibling, 0, 0, 'separate thread after AJAX freeze' );
            my $frozen_recent = $recent->()->content;
            like(
                $frozen_recent,
                qr/id='state$root_dtalkid'>Screened/,
                'the frozen row still shows as screened'
            );
            unlike( $frozen_recent, $reply_link,
                'Recent Comments omits the frozen screened reply link' );

            my $before = $child_count->();
            like(
                $post_reply->( $owner, unscreen_parent => 1 )->content,
                qr/comment is frozen/i,
                'the owner cannot reply to a frozen screened parent'
            );
            like(
                $post_reply->($stranger)->content,
                qr/non-existent comment/i,
                'a stranger is not told the screened parent is frozen'
            );
            is( $child_count->(), $before, 'rejected replies are not stored' );
            $moderation_state->(
                $root, 1, 1, 'frozen parent after rejected reply with unscreen option'
            );

            ok(
                $moderate->( $commenter, $root, 'unfreeze', 1 )->{error},
                'a comment author cannot unfreeze their own screened comment'
            );
            like(
                $moderate->( $owner, $root, 'unfreeze', 0 ),
                qr/thread has been unfrozen/i,
                'web confirmation reports a successful unfreeze'
            );
            $moderation_state->( $root,  1, 0, 'screened thread root after web unfreeze' );
            $moderation_state->( $child, 0, 0, 'public descendant after web unfreeze' );
            like( $recent->()->content,
                $reply_link, 'Recent Comments offers a reply after unfreezing' );
            $post_reply->($owner);
            is( $child_count->(), $before + 1, 'a reply is stored after unfreezing' );

            like(
                $moderate->( $owner, $comm_root, 'freeze', 0 ),
                qr/thread has been frozen/i,
                'community entry author can freeze through the web form'
            );
            $moderation_state->( $comm_root, 1, 1, 'community thread after web freeze' );

            like( $moderate->( $manager, $comm_root, 'unscreen', 1 )->{newurl},
                qr/mode=screen/, 'community manager can unscreen a frozen comment' );
            $moderation_state->( $comm_root, 0, 1, 'frozen comment after unscreening' );

            like( $moderate->( $manager, $comm_root, 'screen', 1 )->{newurl},
                qr/mode=unscreen/, 'community manager can screen a frozen comment' );
            $moderation_state->( $comm_root, 1, 1, 'frozen comment after screening' );

            like( $moderate->( $manager, $comm_root, 'unfreeze', 1 )->{newurl},
                qr/mode=freeze/, 'community manager can unfreeze through AJAX' );
            $moderation_state->( $comm_root, 1, 0, 'community thread after AJAX unfreeze' );
        };
    };
};

subtest 'Bulk unscreen updates and accounts for the selected screened comments' => sub {
    my $bulk_owner = temp_user();
    $bulk_owner->update_self( { status => 'A' } );
    my $bulk_entry = $bulk_owner->t_post_fake_entry;
    my $username   = $bulk_owner->user;
    my $journalid  = $bulk_owner->id;
    my $itemid     = $bulk_entry->jitemid;
    my $dbcm       = LJ::get_cluster_master($bulk_owner);

    with_fake_memcache {
        my $active   = $bulk_entry->t_enter_comment( u => $author );
        my $screened = $bulk_entry->t_enter_comment( u => $author, state => 'S' );
        my $frozen   = $bulk_entry->t_enter_comment( u => $author, state => 'S' );
        my $other    = $bulk_entry->t_enter_comment( u => $author, state => 'S' );
        LJ::Talk::freeze_thread( $bulk_owner, $itemid, $frozen->jtalkid );

        my $states = sub {
            return [
                map { $_->{state} } LJ::Talk::get_talk2_row_multi(
                    map { [ $bulk_owner, $_->jtalkid ] } ( $active, $screened, $frozen, $other )
                )
            ];
        };
        my $has_screened = sub {
            my %props;
            LJ::load_log_props2( $dbcm, $journalid, [$itemid], \%props );
            return $props{$itemid}{hasscreened};
        };
        my $reply_count = sub {
            return $dbcm->selectrow_array(
                'SELECT replycount FROM log2 WHERE journalid=? AND jitemid=?',
                undef, $journalid, $itemid );
        };

        is_deeply( $states->(), [qw(A S S S)], 'initial states are cached' );
        LJ::Talk::get_talk_data( $bulk_owner, 'L', $itemid );

        test_psgi $app, sub {
            my ($request) = @_;
            my $submit = sub {
                my ( $mode, @selected ) = @_;
                return $request->(
                    POST "http://localhost/talkmulti?as=$username",
                    Content => [
                        journal => $username,
                        ditemid => $bulk_entry->ditemid,
                        mode    => $mode,
                        map { ( 'selected_' . $_->jtalkid => 1 ) } @selected,
                    ],
                );
            };

            my $locker = LJ::get_cluster_master( { unshared => 1 }, $bulk_owner );
            my ($wait) = $dbcm->selectrow_array('SELECT @@SESSION.innodb_lock_wait_timeout');
            $wait = int($wait);
            $dbcm->do('SET SESSION innodb_lock_wait_timeout = 1') or die $dbcm->errstr;
            my ( $failed, $failed_delete );
            my $tested = eval {
                $locker->begin_work or die $locker->errstr;
                $locker->selectrow_array(
                    'SELECT jtalkid FROM talk2 WHERE journalid=? AND jtalkid=? FOR UPDATE',
                    undef, $journalid, $frozen->jtalkid )
                    or die $locker->errstr;
                $failed        = $submit->( 'unscreen', $active, $screened, $frozen );
                $failed_delete = $submit->( 'delete',   $frozen );
                1;
            };
            my $test_error = $@;
            $locker->rollback unless $locker->{AutoCommit};
            $dbcm->do("SET SESSION innodb_lock_wait_timeout = $wait") or die $dbcm->errstr;
            die $test_error unless $tested;

            like(
                $failed->content,
                qr/database temporarily unavailable/i,
                'bulk unscreen reports a failed write'
            );
            like(
                $failed_delete->content,
                qr/database temporarily unavailable/i,
                'bulk delete stops when unscreen fails'
            );
            is_deeply( $states->(), [qw(A S S S)],
                'neither request changes any selected state on failure' );
            is( $reply_count->(), 1, 'failed requests do not change the reply count' );
            ok( $has_screened->(), 'failed requests leave the screened flag set' );

            my $success = $submit->( 'unscreen', $active, $screened, $frozen );
            like(
                $success->content,
                qr/unscreened the selected comments/i,
                'bulk unscreen succeeds on retry'
            );
            is( $reply_count->(), 3, 'only the two screened selections increase the reply count' );
            is_deeply( $states->(), [qw(A A F S)], 'row cache returns the new states' );
            my $talk = LJ::Talk::get_talk_data( $bulk_owner, 'L', $itemid );
            is( $talk->{ $frozen->jtalkid }{state},
                'F', 'thread cache also returns the restored frozen state' );
            ok( $has_screened->(), 'an unselected screened comment keeps the screened flag set' );

            $submit->( 'unscreen', $active, $screened, $frozen, $other );
            is( $reply_count->(), 4, 'repeated selections are not counted again' );
            ok( !$has_screened->(), 'unscreening the last screened comment clears the flag' );
        };
    };
};

done_testing();
