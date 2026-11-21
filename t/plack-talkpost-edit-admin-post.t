# t/plack-talkpost-edit-admin-post.t
#
# Tests for preserving and displaying the "Admin Post" checkbox when editing
# comments in communities across Foundation and legacy talkforms, including
# initial edit render, preview/error redisplay, and saving edits.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use Test::More;
use HTTP::Request;
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use LJ::Comment;
use LJ::S2;
use LJ::S2::ReplyPage;
use LJ::Talk;
use LJ::Test qw(temp_user temp_comm with_fake_memcache);
use S2;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'editAdminPostTest';

my $comm     = temp_comm();
my $admin    = temp_user();
my $member   = temp_user();
my $personal = temp_user();

for my $u ( $admin, $member, $personal ) {
    $u->update_self( { status => 'A' } );
    $u->add_to_class('paid_user');    # enables edit_comments cap
}
$comm->update_self( { status => 'A', opt_whocanreply => 'all', opt_showtalklinks => 'Y' } );
$personal->update_self( { opt_whocanreply => 'all', opt_showtalklinks => 'Y' } );

LJ::set_rel( $comm, $admin, 'A' );
LJ::set_rel( $comm, $admin, 'P' );
LJ::set_rel( $comm, $admin, 'E' );
$admin->join_community( $comm, 1, 1 );
$member->join_community( $comm, 1, 1 );

my $comm_entry = $admin->t_post_fake_entry(
    usejournal      => $comm->user,
    usejournal_okay => 1,
    subject         => 'Community entry',
    body            => 'Community entry body',
);
my $personal_entry = $personal->t_post_fake_entry(
    subject => 'Personal entry',
    body    => 'Personal entry body',
);

my $admin_cmt = $comm_entry->t_enter_comment(
    u       => $admin,
    subject => 'Admin comment',
    body    => 'Original admin comment body',
);
$admin_cmt->set_prop( 'admin_post', 1 );

my $regular_cmt = $comm_entry->t_enter_comment(
    u       => $admin,
    subject => 'Regular comment',
    body    => 'Original regular comment body',
);

my $member_cmt = $comm_entry->t_enter_comment(
    u       => $member,
    subject => 'Member comment',
    body    => 'Original member comment body',
);

my $personal_cmt = $personal_entry->t_enter_comment(
    u       => $personal,
    subject => 'Personal comment',
    body    => 'Original personal comment body',
);

sub admin_checkbox_tag {
    my ($html) = @_;
    if ( $html =~ /(<input\b[^>]*\bname=['"]prop_admin_post['"][^>]*>)/i ) {
        return $1;
    }
    return undef;
}

sub is_checked_tag {
    my ($tag) = @_;
    return defined $tag && $tag =~ /\bchecked(?:\s*=\s*['"]?checked['"]?)?\b/i;
}

sub render_edit_form {
    my ( $journal, $viewer, $entry, $comment ) = @_;
    my $ditemid = $entry->ditemid;
    my $dtalkid = $comment->dtalkid;

    DW::Request->reset;
    my $r = DW::Request::Standard->new(
        HTTP::Request->new( GET => "/$ditemid.html?mode=reply&edit=$dtalkid" ) );
    LJ::set_remote($viewer);

    local $journal->{_s2styleid}   = 0;
    local $journal->{_journalbase} = $journal->journal_base;

    my $ctx  = [ {}, {}, { userpics_position => 'left' }, {}, [], {} ];
    my $opts = {
        r       => $r,
        getargs => { mode => 'reply', edit => $dtalkid },
        ctx     => $ctx,
        ljentry => $entry,
    };
    my $page = LJ::S2::ReplyPage( $journal, $viewer, $opts );
    ok( ref $page eq 'HASH' && ref $page->{form} eq 'HASH', 'ReplyPage returned edit form data' );

    my $html = '';
    local $S2::pout = sub { $html .= join( '', @_ ); };
    S2::Builtin::LJ::ReplyForm__print( $ctx, $page->{form} );

    LJ::set_remote(undef);
    return $html;
}

# Avoid spam-check hooks during comment edits.
no warnings 'redefine';
my $run_hooks = \&LJ::Hooks::run_hooks;
local *LJ::Hooks::run_hooks = sub {
    return if $_[0] eq 'spam_check';
    return $run_hooks->(@_);
};
my $beta   = \&LJ::BetaFeatures::user_in_beta;
my $legacy = 0;
local *LJ::BetaFeatures::user_in_beta = sub {
    return $legacy if ( $_[2] || '' ) eq 'nos2foundation';
    return $beta->(@_);
};
use warnings 'redefine';

with_fake_memcache {
    for my $mode ( 0, 1 ) {
        $legacy = $mode;
        my $label = $legacy ? 'legacy talkform' : 'Foundation talkform';

        subtest "$label: initial ReplyPage edit render" => sub {
            my $admin_html = render_edit_form( $comm, $admin, $comm_entry, $admin_cmt );
            my $admin_tag  = admin_checkbox_tag($admin_html);
            ok( defined $admin_tag, "$label shows Admin Post checkbox when editing admin comment" );
            ok( is_checked_tag($admin_tag),
                "$label pre-checks Admin Post checkbox for an existing admin comment" );

            my $reg_html = render_edit_form( $comm, $admin, $comm_entry, $regular_cmt );
            my $reg_tag  = admin_checkbox_tag($reg_html);
            ok( defined $reg_tag,
                "$label shows Admin Post checkbox when admin edits non-admin comment" );
            ok( !is_checked_tag($reg_tag),
                "$label leaves Admin Post checkbox unchecked for a non-admin comment" );

            my $member_html = render_edit_form( $comm, $member, $comm_entry, $member_cmt );
            ok( !defined admin_checkbox_tag($member_html),
                "$label omits Admin Post checkbox for non-admin community member" );

            my $pers_html =
                render_edit_form( $personal, $personal, $personal_entry, $personal_cmt );
            ok( !defined admin_checkbox_tag($pers_html),
                "$label omits Admin Post checkbox on a personal journal" );
        };
    }

    test_psgi $app, sub {
        my $cb = shift;

        my $post_edit = sub {
            my ( $viewer, $entry, $comment, %extra ) = @_;
            LJ::set_remote($viewer);
            delete $LJ::REQ_GLOBAL{form_auth_chal};
            my $form_auth = LJ::form_auth(1);
            LJ::set_remote(undef);

            return $cb->(
                POST "http://localhost/talkpost_do?as=" . $viewer->user,
                Content => [
                    lj_form_auth => $form_auth,
                    chrp1        => LJ::Talk::generate_chrp1( $entry->journalid, $entry->ditemid ),
                    journal      => $entry->journal->user,
                    itemid       => $entry->ditemid,
                    parenttalkid => 0,
                    replyto      => 0,
                    editid       => $comment->dtalkid,
                    usertype     => 'cookieuser',
                    cookieuser   => $viewer->user,
                    subject      => 'Edited subject',
                    body         => 'Edited comment body ' . rand(),
                    subjecticon  => 'none',
                    %extra,
                ],
            );
        };

        for my $mode ( 0, 1 ) {
            $legacy = $mode;
            my $label = $legacy ? 'legacy talkform' : 'Foundation talkform';

            subtest "$label: preview and error redisplay preserve Admin Post state" => sub {
                my $res_checked = $post_edit->(
                    $admin, $comm_entry, $admin_cmt,
                    submitpreview   => 1,
                    prop_admin_post => 1,
                );
                is( $res_checked->code, 200, "$label preview with admin_post returns 200" );
                like( $res_checked->content, qr/admin-post-icon/,
                    "$label preview renders admin post badge when checked" );
                my $tag_checked = admin_checkbox_tag( $res_checked->content );
                ok( defined $tag_checked,
                    "$label preview redisplays Admin Post checkbox when checked" );
                ok( is_checked_tag($tag_checked),
                    "$label preview keeps Admin Post checkbox checked" );

                my $res_unchecked =
                    $post_edit->( $admin, $comm_entry, $admin_cmt, submitpreview => 1, );
                is( $res_unchecked->code, 200, "$label preview without admin_post returns 200" );
                unlike( $res_unchecked->content, qr/admin-post-icon/,
                    "$label preview omits admin post badge when unchecked" );
                my $tag_unchecked = admin_checkbox_tag( $res_unchecked->content );
                ok( defined $tag_unchecked,
                    "$label preview redisplays Admin Post checkbox when unchecked" );
                ok( !is_checked_tag($tag_unchecked),
                    "$label preview keeps Admin Post checkbox unchecked after user clears it" );

                my $res_err_checked = $post_edit->(
                    $admin, $comm_entry, $admin_cmt,
                    body            => '',
                    prop_admin_post => 1,
                );
                is( $res_err_checked->code, 200, "$label error redisplay returns 200" );
                my $tag_err = admin_checkbox_tag( $res_err_checked->content );
                ok( defined $tag_err, "$label error redisplay includes Admin Post checkbox" );
                ok( is_checked_tag($tag_err),
                    "$label error redisplay keeps Admin Post checkbox checked" );

                my $res_err_unchecked =
                    $post_edit->( $admin, $comm_entry, $admin_cmt, body => '', );
                my $tag_err_un = admin_checkbox_tag( $res_err_unchecked->content );
                ok( defined $tag_err_un,
                    "$label error redisplay includes Admin Post checkbox when unchecked" );
                ok( !is_checked_tag($tag_err_un),
                    "$label error redisplay keeps Admin Post checkbox unchecked" );
            };
        }

        $legacy = 0;
        subtest 'saving edited comments updates admin_post accurately' => sub {
            my $res_keep = $post_edit->( $admin, $comm_entry, $admin_cmt, prop_admin_post => 1, );
            is( $res_keep->code, 303, 'save edit keeping admin_post redirects' );
            my $reloaded = LJ::Comment->new( $comm, dtalkid => $admin_cmt->dtalkid );
            is( $reloaded->admin_post, 1, 'admin_post remains set when checkbox stays checked' );

            my $res_clear = $post_edit->( $admin, $comm_entry, $admin_cmt );
            is( $res_clear->code, 303, 'save edit clearing admin_post redirects' );
            $reloaded = LJ::Comment->new( $comm, dtalkid => $admin_cmt->dtalkid );
            is( $reloaded->admin_post, 0, 'admin_post is cleared when checkbox is unchecked' );

            my $res_enable =
                $post_edit->( $admin, $comm_entry, $regular_cmt, prop_admin_post => 1, );
            is( $res_enable->code, 303, 'save edit enabling admin_post redirects' );
            $reloaded = LJ::Comment->new( $comm, dtalkid => $regular_cmt->dtalkid );
            is( $reloaded->admin_post, 1,
                'admin_post can be enabled when editing a non-admin comment' );
        };
    };
};

done_testing();
