# t/plack-talkscreen.t
#
# Moderating a thread must preserve screening and freezing independently.
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

my $owner     = temp_user();
my $commenter = temp_user();
my $stranger  = temp_user();
my $manager   = temp_user();
my $community = temp_comm();
LJ::set_rel( $community, $manager, 'A' );

my $personal_entry  = $owner->t_post_fake_entry;
my $community_entry = $owner->t_post_fake_entry(
    usejournal      => $community->user,
    usejournal_okay => 1
);

sub moderation_state {
    my ( $comment, $screened, $frozen, $description ) = @_;
    my ( $journal, $jtalkid ) = ( $comment->journal, $comment->jtalkid );
    LJ::Comment->reset_singletons;
    my $fresh = LJ::Comment->new( $journal, jtalkid => $jtalkid );
    is( $fresh->is_screened,             $screened,        "$description: screening persists" );
    is( $fresh->is_frozen,               $frozen,          "$description: freezing persists" );
    is( !!$fresh->visible_to($stranger), !!( !$screened ), "$description: stranger visibility" );
}

with_fake_memcache {
    my $root      = $personal_entry->t_enter_comment( u => $commenter, state => 'S' );
    my $child     = $root->t_reply( u => $commenter );
    my $sibling   = $personal_entry->t_enter_comment( u => $commenter );
    my $comm_root = $community_entry->t_enter_comment( u => $commenter, state => 'S' );

    test_psgi $app, sub {
        my ($request) = @_;
        my $moderate = sub {
            my ( $actor, $comment, $mode, $ajax ) = @_;
            LJ::set_remote($actor);
            delete $LJ::REQ_GLOBAL{form_auth_chal};
            my $auth = LJ::form_auth(1);
            LJ::set_remote(undef);

            my $endpoint   = $ajax ? '__rpc_talkscreen?jsmode=1&json=1&' : 'talkscreen?';
            my $actor_name = $actor->user;
            my $response   = $request->(
                POST "http://localhost/${endpoint}as=$actor_name",
                Content => [
                    mode         => $mode,
                    journal      => $comment->journal->user,
                    talkid       => $comment->dtalkid,
                    confirm      => 'Y',
                    lj_form_auth => $auth,
                ],
            );

            if ($ajax) {
                is( $response->code, 200, "AJAX $mode returns a response" );
                return decode_json( $response->content );
            }
            return $response->content;
        };

        like( $moderate->( $commenter, $root, 'freeze', 1 )->{error},
            qr/permission/i, 'a comment author cannot freeze their own screened comment' );
        ok(
            $moderate->( $stranger, $root, 'freeze', 1 )->{error},
            'a stranger cannot moderate a screened comment'
        );
        moderation_state( $root, 1, 0, 'unauthorized freeze' );

        like( $moderate->( $owner, $root, 'freeze', 1 )->{newurl},
            qr/mode=unfreeze/, 'AJAX freeze offers the inverse action' );
        moderation_state( $root,    1, 1, 'screened thread root after AJAX freeze' );
        moderation_state( $child,   0, 1, 'public descendant after AJAX freeze' );
        moderation_state( $sibling, 0, 0, 'separate thread after AJAX freeze' );

        ok(
            $moderate->( $commenter, $root, 'unfreeze', 1 )->{error},
            'a comment author cannot unfreeze their own screened comment'
        );
        like(
            $moderate->( $owner, $root, 'unfreeze', 0 ),
            qr/thread has been unfrozen/i,
            'web confirmation reports a successful unfreeze'
        );
        moderation_state( $root,  1, 0, 'screened thread root after web unfreeze' );
        moderation_state( $child, 0, 0, 'public descendant after web unfreeze' );

        like(
            $moderate->( $owner, $comm_root, 'freeze', 0 ),
            qr/thread has been frozen/i,
            'community entry author can freeze through the web form'
        );
        moderation_state( $comm_root, 1, 1, 'community thread after web freeze' );

        like( $moderate->( $manager, $comm_root, 'unscreen', 1 )->{newurl},
            qr/mode=screen/, 'community manager can unscreen a frozen comment' );
        moderation_state( $comm_root, 0, 1, 'frozen comment after unscreening' );

        like( $moderate->( $manager, $comm_root, 'screen', 1 )->{newurl},
            qr/mode=unscreen/, 'community manager can screen a frozen comment' );
        moderation_state( $comm_root, 1, 1, 'frozen comment after screening' );

        like( $moderate->( $manager, $comm_root, 'unfreeze', 1 )->{newurl},
            qr/mode=freeze/, 'community manager can unfreeze through AJAX' );
        moderation_state( $comm_root, 1, 0, 'community thread after AJAX unfreeze' );
    };
};

done_testing;
