# t/controlstrip-community-invites.t
#
# Test community membership actions in the navigation strip.
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

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::AccountSwitcher;
use DW::Request::Standard;
use DW::Template;
use HTTP::Request;
use LJ::Community;
use LJ::Session;
use LJ::Test qw( temp_user temp_comm );
use LJ::Web;
use LJ::Widget::Search;

# The Plack test runtime does not load the Apache-only BML handler. Supply
# deterministic language keys without importing that legacy server dependency.
{

    package ControlStripTestLanguage;
    sub TIEHASH { bless {}, $_[0] }
    sub FETCH { $_[1] }
}
local %BML::ML;
tie %BML::ML, 'ControlStripTestLanguage';

# Keep unrelated presentation out of the test. Invitation and relationship
# lookups use real temporary users and database rows.
no warnings 'redefine';
local *BML::ml                       = sub { $_[0] };
local *DW::AccountSwitcher::accounts = sub { return () };
local *LJ::Widget::Search::render    = sub { return '' };
local *DW::Template::template_string = sub {
    my ( $class, $file, $vars ) = @_;
    die "Unexpected template: $file" unless $file eq 'journal/controlstrip.tt';
    return join "\n", @{ $vars->{actionlinks} };
};
use warnings 'redefine';

local $LJ::DISABLED{esn}           = 1;
local $LJ::DISABLED{control_strip} = 0;

my $admin     = temp_user();
my $viewer    = temp_user();
my $outsider  = temp_user();
my $comm      = temp_comm();
my $othercomm = temp_comm();

for my $cu ( $comm, $othercomm ) {
    LJ::set_rel( $cu, $admin, 'A' );
    LJ::start_request();
    $cu->set_comm_settings( $admin, { membership => 'moderated', postlevel => 'members' } );
    $cu->set_prop( stylesys => 1 );
}

sub strip_actions {
    my ( $remote, $journal ) = @_;
    LJ::start_request();
    DW::Request->reset;
    my $request = HTTP::Request->new( GET => 'http://www.example.test/' );
    $request->header( Host => 'www.example.test' );
    DW::Request::Standard->new($request);
    LJ::Session->create( $remote, nolog => 1, defer_login => 1 )
        or die "Cannot create test session"
        if $remote && !$remote->session;
    LJ::set_remote($remote);

    # The real request router supplies the journal for the visibility hook.
    local $LJ::ACTIVE_JOURNAL = $journal;
    return LJ::control_strip( user => $journal->user, view => 'recent' );
}

my $accept     = qr{<a href='\Q$LJ::SITEROOT\E/manage/invites'>[^<]+</a>};
my $circle_url = "$LJ::SITEROOT/circle/$comm->{user}/edit";
my $join       = qr{<a href='\Q$circle_url\E'>web\.controlstrip\.links\.joincomm</a>};
my $leave      = qr{<a href='\Q$circle_url\E'>web\.controlstrip\.links\.leavecomm</a>};

like( strip_actions( $viewer, $comm ), $join, 'uninvited visitor can request membership' );
ok( $viewer->send_comm_invite( $othercomm, $admin, ['member'] ), 'invite to another community' );
my $actions = strip_actions( $viewer, $comm );
like( $actions, $join, 'invitation to another community does not replace Join' );
unlike( $actions, $accept, 'invitation must match the displayed community' );

ok( $viewer->send_comm_invite( $comm, $admin, ['member'] ), 'invite visitor to community' );
$actions = strip_actions( $viewer, $comm );
like( $actions, $accept, 'invited non-watcher gets the invitation management link' );
unlike( $actions, $join, 'invited non-watcher does not get a join request link' );
unlike( strip_actions( $outsider, $comm ), $accept, 'invitation belongs only to its recipient' );

ok( $viewer->add_edge( $comm, watch => { nonotify => 1 } ), 'subscribe without joining' );
$actions = strip_actions( $viewer, $comm );
like( $actions, $accept, 'invited watcher gets the invitation management link' );
unlike( $actions, $join, 'invited watcher does not get a join request link' );

$comm->set_comm_settings( $admin, { membership => 'closed' } );
$actions = strip_actions( $viewer, $comm );
like( $actions, qr/This is a closed community/, 'closed community status is preserved' );
unlike( $actions, $accept, 'closed community does not offer invitation acceptance' );
unlike( $actions, $join,   'closed community does not offer Join' );
$comm->set_comm_settings( $admin, { membership => 'moderated' } );

$viewer->do(
    'UPDATE inviterecv SET recvtime = UNIX_TIMESTAMP() - 31 * 86400 '
        . 'WHERE userid = ? AND commid = ?',
    undef, $viewer->id, $comm->id
) or die $viewer->errstr;
$actions = strip_actions( $viewer, $comm );
like( $actions, $join, 'expired invitation restores Join' );
unlike( $actions, $accept, 'expired invitation does not offer acceptance' );

ok( $viewer->send_comm_invite( $comm, $admin, ['member'] ), 'reissue invitation' );
ok( $comm->revoke_invites( $viewer->id ), 'revoke invitation' );
$actions = strip_actions( $viewer, $comm );
like( $actions, $join, 'revoked invitation restores Join' );
unlike( $actions, $accept, 'revoked invitation does not offer acceptance' );

ok( $viewer->send_comm_invite( $comm, $admin, ['member'] ), 'invite before accepting' );
ok( $viewer->accept_comm_invite($comm), 'accept invitation' );
$actions = strip_actions( $viewer, $comm );
ok( $viewer->member_of($comm), 'acceptance creates membership' );
like( $actions, $leave, 'member who watches can leave' );
unlike( $actions, $accept, 'accepted invitation is no longer offered' );
unlike( $actions, $join,   'member is not asked to join again' );

ok( $viewer->remove_edge( $comm, watch => { nonotify => 1 } ), 'unsubscribe while a member' );
ok( $viewer->send_comm_invite( $comm, $admin, ['post'] ), 'offer additional member privileges' );
$actions = strip_actions( $viewer, $comm );
like( $actions, $leave, 'member who does not watch can leave' );
unlike( $actions, $accept, 'additional privileges do not replace member actions' );

$actions = strip_actions( $admin, $comm );
like(
    $actions,
    qr/web\.controlstrip\.links\.managecomminvites/,
    'maintainer actions are preserved'
);
unlike( $actions, $accept, 'maintainer is not asked to accept an invitation' );

$actions = strip_actions( undef, $comm );
unlike( $actions, $accept, 'logged-out visitor has no invitation action' );
unlike( $actions, $join,   'logged-out visitor has no membership action' );

done_testing();
