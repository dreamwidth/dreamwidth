# t/plack-icon-view-order.t
#
# Verify that icon listing sort choices follow the signed-in viewer.
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
use HTTP::Request::Common;
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::Request::Standard;
use LJ::S2;
use LJ::Session;
use LJ::Test qw(temp_user with_fake_memcache);
use LJ::Userpic;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'iconOrderTest';

my $viewer = temp_user();
my $owner  = temp_user();
$_->update_self( { status => 'A' } ) for ( $viewer, $owner );

my ( @pics, @sessions );

END {
    $_->destroy for @sessions;
    $_->delete  for @pics;
}

for my $account ( $viewer, $owner ) {
    for my $fixture ( [ 'good.png', 'zebra order' ], [ 'good.gif', 'apple order' ] ) {
        my ( $file, $keyword ) = @$fixture;
        open my $fh, '<:raw', "$ENV{LJHOME}/t/data/userpics/$file" or die "open $file: $!";
        my $data = do { local $/; <$fh> };
        close $fh;
        my $pic = LJ::Userpic->create( $account, data => \$data, nonotify => 1 );
        $pic->set_keywords($keyword);
        push @pics, $pic;
    }
}

my $manage  = 'http://localhost/manage/icons?as=' . $viewer->user;
my $journal = 'http://localhost/users/' . $owner->user . '/icons';

sub journal_icons {
    my ( $account, $get, $style_order ) = @_;
    DW::Request->reset;
    DW::Request::Standard->new( GET $journal );
    my $remote = $account ? LJ::load_userid( $account->id, 1 ) : undef;
    local $owner->{_s2styleid}   = 0;
    local $owner->{_journalbase} = $owner->journal_base;
    my $ctx = [];
    $ctx->[S2::PROPS] = { num_items_icons => 0, icons_page_sort => $style_order };
    my $page = LJ::S2::IconsPage( $owner, $remote, { ctx => $ctx, getargs => $get || {} } );
    DW::Request->reset;
    return join ', ', map { @{ $_->{keywords} } } @{ $page->{icons} };
}

sub form_token {
    my ($remote) = @_;
    DW::Request->reset;
    DW::Request::Standard->new( GET $manage );
    local $LJ::REQ_GLOBAL{form_auth_chal};
    LJ::set_remote($remote);
    my $token = LJ::form_auth(1);
    LJ::set_remote(undef);
    DW::Request->reset;
    return $token;
}

sub session_cookie {
    my ($account) = @_;
    my $session = LJ::Session->create( $account, nolog => 1, defer_login => 1 )
        or die 'could not create login session';
    push @sessions, $session;
    return join '; ', 'ljmastersession=' . $session->master_cookie_string,
        'ljloggedin=' . $session->loggedin_cookie_string;
}

with_fake_memcache {
    test_psgi $app, sub {
        my ($request) = @_;
        my $upload    = 'zebra order, apple order';
        my $keyword   = 'apple order, zebra order';

        my $manage_icons = sub {
            my ($url) = @_;
            my $res = $request->( GET $url );
            is( $res->code, 200, 'Manage Icons renders' );
            my @textboxes = $res->content =~ /(<input type="text"[^>]*\bid="kw_\d+"[^>]*>)/g;
            return join ', ', map { /\bvalue="([^"]*)"/ } @textboxes;
        };

        my $view    = "$journal?as=" . $viewer->user;
        my $token   = form_token($viewer);
        my $sort_on = sub {
            my ( $url, $order, $auth ) = @_;
            return $request->(
                POST $url, Content => [ icon_view_order => $order, lj_form_auth => $auth ]
            );
        };

        is( $manage_icons->($manage), $upload, 'Manage Icons starts in upload order' );
        is( journal_icons($viewer),   $upload, 'Icons starts in upload order' );
        is( journal_icons( $viewer, {}, 'keyword' ),
            $keyword, 'Icons uses the journal default before the viewer chooses an order' );

        my $save = $sort_on->( $manage, 'keyword', $token );
        is( $save->code,              303,      'Manage Icons saves the choice and redirects' );
        is( $manage_icons->($manage), $keyword, 'Manage Icons remembers the keyword choice' );
        is( journal_icons($viewer),   $keyword, 'Icons uses the same viewer preference' );
        is( journal_icons($owner),    $upload,  'journal owner is unaffected' );
        is( journal_icons(undef),     $upload,  'logged-out visitors are unaffected' );

        is( $manage_icons->("$manage&keywordSort=0"),
            $upload, 'explicit Manage Icons query can override the default' );
        is( journal_icons( $viewer, { sortorder => 'upload' } ),
            $upload, 'explicit Icons query can override the default' );
        is( journal_icons($viewer), $keyword, 'viewing an explicit URL does not save its order' );

        my $invalid = $sort_on->( "$view&view=all", 'upload', form_token($owner) );
        is( $invalid->code, 403, "another account's form token cannot save a preference" );
        $invalid = $sort_on->( "$view&view=all", 'invalid', $token );
        is( $invalid->code, 400, 'unknown sort order is rejected' );
        $invalid = $sort_on->( $journal, 'upload', $token );
        is( $invalid->code, 403, 'logged-out visitors cannot save a choice' );
        $invalid = $sort_on->( $manage, 'upload', form_token($owner) );
        is( $invalid->code,         403,      'Manage Icons also rejects a mismatched form token' );
        is( journal_icons($viewer), $keyword, 'rejected requests do not change the order' );

        $save = $sort_on->( "$view&view=all&sortorder=keyword", 'upload', $token );
        is( $save->code, 303, 'Icons saves upload order and redirects' );
        like( $save->header('Location') // '',
            qr{\?view=all\z}, 'redirect keeps view mode but drops the explicit sort override' );
        is( journal_icons($viewer), $upload, 'Icons remembers the upload choice' );
        is( journal_icons( $viewer, {}, 'keyword' ),
            $upload,
            'Icons uses the saved upload choice even when the journal defaults to keyword' );
        is( $manage_icons->($manage), $upload, 'Manage Icons follows the updated choice' );
        is( $manage_icons->("$manage&keywordSort=1"),
            $keyword, 'legacy keyword link still works over a saved upload choice' );
        is( $manage_icons->($manage), $upload, 'the legacy link does not change the saved choice' );

        local $LJ::CAP{1}->{userpicselect} = 1;
        my $cookie       = session_cookie($viewer);
        my $other_cookie = session_cookie($viewer);
        my $picker       = 'http://localhost/inbox/new/compose';
        my $rpc          = 'http://localhost/__rpc_iconbrowser_save';
        my $picker_form  = sub {
            my ($expected_order) = @_;
            my $res = $request->( GET $picker, Cookie => $cookie );
            is( $res->code, 200, 'picker page renders for the signed-in viewer' );
            my ($form) = $res->content =~ m{(<form\b[^>]*\bid="compose"[^>]*>.*?</form>)}s;
            like(
                $form // '',
                qr/data-iconbrowser-keywordorder="$expected_order"/,
                'Foundation picker opens with the saved preference'
            );
            my ($auth) = ( $form // '' ) =~ /name="lj_form_auth"\s+value="([^"]+)"/;
            return $auth;
        };
        my $picker_auth = $picker_form->(0);
        ok( $picker_auth, 'picker form contains a session token' );
        my $forged_auth = ( $picker_auth // '' ) =~ s/([[:xdigit:]])\z/$1 eq '0' ? '1' : '0'/er;

        my $picker_save = sub {
            my ( $session, $order, $auth ) = @_;
            return $request->(
                POST $rpc,
                ( defined $session ? ( Cookie => $session ) : () ),
                Content =>
                    [ keywordorder => $order, defined $auth ? ( lj_form_auth => $auth ) : () ]
            );
        };
        is( $picker_save->( $cookie, 'true', undef )->code, 403, 'picker requires a token' );
        is( $picker_save->( $cookie, 'true', $forged_auth )->code,
            403, 'picker rejects a forged token for the current session' );
        is( $picker_save->( $other_cookie, 'true', $picker_auth )->code,
            403, 'picker rejects a token from a different session of the same user' );
        is( $picker_save->( undef, 'true', $picker_auth )->code,
            403, 'logged-out visitors cannot save via the picker' );
        is( journal_icons($viewer), $upload, 'rejected picker requests leave the order unchanged' );

        is( $picker_save->( $cookie, 'true', $picker_auth )->code,
            200, 'picker saves keyword order with a valid token' );
        is( $picker_save->( $cookie, 'invalid', $picker_auth )->code,
            400, 'picker rejects unknown order values without resetting the saved order' );
        is( journal_icons($viewer), $keyword, 'Icons follows the keyword choice from the picker' );
        is( $manage_icons->($manage), $keyword, 'Manage Icons follows the keyword choice' );
        $picker_form->(1);

        is( $picker_save->( $cookie, 'false', $picker_auth )->code,
            200, 'picker saves upload order with a valid token' );
        is( journal_icons($viewer),   $upload, 'Icons follows the upload choice from the picker' );
        is( $manage_icons->($manage), $upload, 'Manage Icons follows the upload choice' );
        $picker_form->(0);
    };
};

done_testing;
