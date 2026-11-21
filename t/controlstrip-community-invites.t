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

use DateTime;
use DW::AccountSwitcher;
use DW::Controller::Manage::Invites;
use DW::Controller::RPC::MiscLegacy;
use DW::Request::Standard;
use DW::Template;
use HTTP::Request;
use LJ::Community;
use LJ::JSON qw( from_json );
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
local $LJ::DISABLED{adult_content} = 0;

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

sub viewer_request {
    my ( $remote, $path ) = @_;
    LJ::start_request();
    DW::Request->reset;
    my $request = HTTP::Request->new( GET => "http://www.example.test$path" );
    $request->header( Host => 'www.example.test' );
    my $dw_request = DW::Request::Standard->new($request);
    LJ::Session->create( $remote, nolog => 1, defer_login => 1 )
        or die "Cannot create test session"
        if $remote && !$remote->session;
    LJ::set_remote($remote);
    return $dw_request;
}

sub strip_actions {
    my ( $remote, $journal ) = @_;
    viewer_request( $remote, '/' );

    # The real request router supplies the journal for the visibility hook.
    local $LJ::ACTIVE_JOURNAL = $journal;
    return LJ::control_strip( user => $journal->user, view => 'recent' );
}

sub hover_info {
    my ( $remote, $journal ) = @_;
    my $request = viewer_request( $remote, '/__rpc_ctxpopup?mode=getinfo&user=' . $journal->user );
    DW::Controller::RPC::MiscLegacy::ctxpopup_handler();
    return from_json( $request->response_content );
}

sub post_request {
    my ( $remote, $path, $params ) = @_;
    LJ::start_request();
    DW::Request->reset;
    my $request = HTTP::Request->new( POST => "http://www.example.test$path" );
    $request->header( Host           => 'www.example.test' );
    $request->header( 'Content-Type' => 'application/x-www-form-urlencoded' );
    $request->content(
        join( '&', map { LJ::eurl($_) . '=' . LJ::eurl( $params->{$_} ) } sort keys %$params ) );
    my $dw_request = DW::Request::Standard->new($request);
    LJ::Session->create( $remote, nolog => 1, defer_login => 1 )
        or die "Cannot create test session"
        if $remote && !$remote->session;
    LJ::set_remote($remote);
    return $dw_request;
}

sub hover_accept {
    my ( $remote, $journal ) = @_;
    my $info    = hover_info( $remote, $journal );
    my $request = post_request(
        $remote,
        '/__rpc_changerelation',
        {
            target     => $journal->user,
            action     => 'accept',
            auth_token => $info->{accept_authtoken},
        },
    );
    DW::Controller::RPC::MiscLegacy::change_relation_handler();
    return from_json( $request->response_content );
}

sub form_accept {
    my ( $remote, $journal ) = @_;
    viewer_request( $remote, '/manage/invites' );
    my $auth = LJ::form_auth(1);
    post_request(
        $remote,
        '/manage/invites',
        {
            lj_form_auth                => $auth,
            'pending_' . $journal->id() => 'yes',
        },
    );
    no warnings 'redefine';
    local *DW::Template::render_template = sub { $_[2] };
    return DW::Controller::Manage::Invites::invites_handler();
}

sub maintainer_add_logs {
    my ( $journal, $target ) = @_;
    return $journal->selectall_arrayref(
        "SELECT actiontarget, remoteid FROM userlog "
            . "WHERE userid = ? AND action = 'maintainer_add' AND actiontarget = ?",
        undef, $journal->id, $target->id
    ) || [];
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
like( $actions, $accept, 'closed community offers acceptance to an invited watcher' );
unlike( $actions, $join, 'closed community does not offer Join to an invited watcher' );
ok( $viewer->remove_edge( $comm, watch => { nonotify => 1 } ), 'unsubscribe while invited' );
$actions = strip_actions( $viewer, $comm );
like( $actions, $accept, 'closed community offers acceptance to an invited non-watcher' );
unlike( $actions, $join, 'closed community does not offer Join to an invited non-watcher' );
$actions = strip_actions( $outsider, $comm );
like( $actions, qr/This is a closed community/, 'closed status remains for uninvited visitors' );
unlike( $actions, $accept, 'closed community does not offer acceptance to uninvited visitors' );
unlike( $actions, $join,   'closed community does not offer Join to uninvited visitors' );

my $hover = hover_info( $viewer, $comm );
ok( $hover->{success} && $hover->{is_invited}, 'hover offers acceptance before the ban' );
viewer_request( $admin, '/' );
ok( $comm->ban_user($viewer), 'community bans the invited nonmember' );
ok( scalar( grep { $_->[0] == $comm->id } @{ $viewer->get_pending_invites } ),
    'membership invitation remains pending after the ban' );
$actions = strip_actions( $viewer, $comm );
like( $actions, qr/This is a closed community/, 'closed status for banned non-watcher' );
unlike( $actions, $accept, 'strip does not offer acceptance to banned non-watcher' );
$hover = hover_info( $viewer, $comm );
ok(
    $hover->{success} && $hover->{is_closed_membership},
    'hover still describes the closed community'
);
is( $hover->{is_invited}, 0, 'hover does not offer acceptance to the banned invitee' );

ok( $viewer->add_edge( $comm, watch => { nonotify => 1 } ), 'resubscribe while invited' );
$actions = strip_actions( $viewer, $comm );
like( $actions, qr/This is a closed community/, 'closed status for banned watcher' );
unlike( $actions, $accept, 'strip does not offer acceptance to banned watcher' );
viewer_request( $admin, '/' );
ok( $comm->unban_user_multi( $viewer->id ), 'community lifts the ban' );
like( strip_actions( $viewer, $comm ),
    $accept, 'strip offers the pending invite again after unban' );
ok(
    hover_info( $viewer, $comm )->{is_invited},
    'hover offers the pending invite again after unban'
);

ok( $outsider->send_comm_invite( $comm, $admin, ['post'] ), 'issue a posting-only invitation' );
viewer_request( $admin, '/' );
ok( $comm->ban_user($outsider), 'community bans the recipient of the posting-only invitation' );
like( strip_actions( $outsider, $comm ),
    $accept, 'ban does not hide a posting-only invitation in the strip' );
ok( hover_info( $outsider, $comm )->{is_invited},
    'ban does not hide a posting-only invitation in the hover' );

# Pending membership invitations that become age-ineligible when a closed
# community switches to explicit adult content must not be offered in the strip
# or hover menus, while role-only and eligible-adult offers remain available.
{
    my $minor      = temp_user();
    my $no_age     = temp_user();
    my $adult      = temp_user();
    my $role_minor = temp_user();
    $minor->set_prop( init_bdate => DateTime->now->subtract( years => 17 )->ymd );
    $adult->set_prop( init_bdate => DateTime->now->subtract( years => 18 )->ymd );
    $role_minor->set_prop( init_bdate => DateTime->now->subtract( years => 17 )->ymd );

    ok(
        $minor->send_comm_invite( $comm, $admin, ['member'] ),
        'invite minor before community becomes explicit'
    );
    ok(
        $no_age->send_comm_invite( $comm, $admin, ['member'] ),
        'invite user without recorded age before community becomes explicit'
    );
    ok(
        $adult->send_comm_invite( $comm, $admin, ['member'] ),
        'invite adult before community becomes explicit'
    );
    ok( $role_minor->send_comm_invite( $comm, $admin, ['post'] ),
        'issue posting-only invitation to minor before community becomes explicit' );

    like( strip_actions( $minor, $comm ),
        $accept, 'strip offers membership invite to minor before explicit rating' );
    ok( hover_info( $minor, $comm )->{is_invited},
        'hover offers membership invite to minor before explicit rating' );
    like( strip_actions( $no_age, $comm ),
        $accept, 'strip offers membership invite without age before explicit rating' );
    ok( hover_info( $no_age, $comm )->{is_invited},
        'hover offers membership invite without age before explicit rating' );

    $comm->set_prop( adult_content => 'explicit' );
    ok(
        scalar( grep { $_->[0] == $comm->id } @{ $minor->get_pending_invites } ),
        'minor membership invitation remains pending after rating change'
    );
    ok(
        scalar( grep { $_->[0] == $comm->id } @{ $no_age->get_pending_invites } ),
        'no-age membership invitation remains pending after rating change'
    );

    $actions = strip_actions( $minor, $comm );
    like( $actions, qr/This is a closed community/, 'closed status for minor non-watcher' );
    unlike( $actions, $accept, 'strip hides age-ineligible invite for minor non-watcher' );
    $hover = hover_info( $minor, $comm );
    ok(
        $hover->{success} && $hover->{is_closed_membership},
        'hover describes closed explicit community for minor'
    );
    is( $hover->{is_invited}, 0, 'hover hides age-ineligible invite for minor' );

    ok( $minor->add_edge( $comm, watch => { nonotify => 1 } ), 'minor subscribes while invited' );
    $actions = strip_actions( $minor, $comm );
    like( $actions, qr/This is a closed community/, 'closed status for minor watcher' );
    unlike( $actions, $accept, 'strip hides age-ineligible invite for minor watcher' );

    $actions = strip_actions( $no_age, $comm );
    like( $actions, qr/This is a closed community/, 'closed status for no-age invitee' );
    unlike( $actions, $accept, 'strip hides age-ineligible invite for no-age invitee' );
    $hover = hover_info( $no_age, $comm );
    is( $hover->{is_invited}, 0, 'hover hides age-ineligible invite for no-age invitee' );

    DW::Request->reset;
    is( $no_age->should_offer_comm_invite($comm),
        0, 'should_offer_comm_invite works without an active web request for no-age user' );

    like( strip_actions( $adult, $comm ),
        $accept, 'strip still offers membership invite to adult for explicit community' );
    ok( hover_info( $adult, $comm )->{is_invited},
        'hover still offers membership invite to adult for explicit community' );

    like( strip_actions( $role_minor, $comm ),
        $accept, 'explicit rating does not hide posting-only invite in the strip' );
    ok( hover_info( $role_minor, $comm )->{is_invited},
        'explicit rating does not hide posting-only invite in the hover' );

    $no_age->set_prop( init_bdate => DateTime->now->subtract( years => 20 )->ymd );
    like( strip_actions( $no_age, $comm ),
        $accept, 'strip offers pending invite again once adult age is recorded' );
    ok( hover_info( $no_age, $comm )->{is_invited},
        'hover offers pending invite again once adult age is recorded' );

    $comm->set_prop( adult_content => 'none' );
    like( strip_actions( $minor, $comm ),
        $accept, 'strip offers pending invite again when explicit rating is removed' );
    ok( hover_info( $minor, $comm )->{is_invited},
        'hover offers pending invite again when explicit rating is removed' );
}

# Accepting a closed-community admin invitation through either the hover RPC or
# the invitations form must log maintainer_add and send notification mail once.
{
    my @sent_mail;
    no warnings 'redefine';
    local *LJ::send_mail = sub { push @sent_mail, $_[0]; return 1 };
    use warnings 'redefine';

    my $hover_admin = temp_user();
    ok(
        $hover_admin->send_comm_invite( $comm, $admin, [ 'member', 'admin' ] ),
        'send closed-community member+admin invitation for hover acceptance'
    );
    @sent_mail = ();
    my $rpc = hover_accept( $hover_admin, $comm );
    LJ::start_request();
    ok( $rpc->{success} && $rpc->{is_member}, 'hover RPC accepts closed-community admin invite' );
    ok( $hover_admin->member_of($comm),       'hover acceptance grants membership' );
    ok( $hover_admin->can_manage($comm),      'hover acceptance grants admin edge' );
    ok( !scalar( grep { $_->[0] == $comm->id } @{ $hover_admin->get_pending_invites } ),
        'hover acceptance consumes the pending invitation' );
    my $hover_logs = maintainer_add_logs( $comm, $hover_admin );
    is( scalar @$hover_logs, 1, 'hover acceptance logs exactly one maintainer_add event' );
    is( $hover_logs->[0]->[1], $admin->id, 'hover maintainer_add records inviting maintainer' );
    is( scalar @sent_mail, 1, 'hover acceptance sends exactly one admin notification email' );
    is( $sent_mail[0]->{to}, $hover_admin->email_raw, 'hover admin email targets new maintainer' );

    my $form_admin = temp_user();
    ok(
        $form_admin->send_comm_invite( $comm, $admin, [ 'member', 'admin' ] ),
        'send closed-community member+admin invitation for form acceptance'
    );
    @sent_mail = ();
    my $rv = form_accept( $form_admin, $comm );
    LJ::start_request();
    ok(
        $rv->{responses} && @{ $rv->{responses}->{accepted} || [] } == 1,
        'invitations form accepts closed-community admin invite'
    );
    ok( $form_admin->member_of($comm),  'form acceptance grants membership' );
    ok( $form_admin->can_manage($comm), 'form acceptance grants admin edge' );
    ok( !scalar( grep { $_->[0] == $comm->id } @{ $form_admin->get_pending_invites } ),
        'form acceptance consumes the pending invitation' );
    my $form_logs = maintainer_add_logs( $comm, $form_admin );
    is( scalar @$form_logs,   1,          'form acceptance logs exactly one maintainer_add event' );
    is( $form_logs->[0]->[1], $admin->id, 'form maintainer_add records inviting maintainer' );
    is( scalar @sent_mail, 1, 'form acceptance sends exactly one admin notification email' );
    is( $sent_mail[0]->{to}, $form_admin->email_raw, 'form admin email targets new maintainer' );

    my $member_only = temp_user();
    ok(
        $member_only->send_comm_invite( $comm, $admin, ['member'] ),
        'send closed-community member-only invitation for hover acceptance'
    );
    @sent_mail = ();
    $rpc       = hover_accept( $member_only, $comm );
    LJ::start_request();
    ok( $rpc->{success} && $rpc->{is_member}, 'hover RPC accepts member-only invitation' );
    ok( !$member_only->can_manage($comm),     'member-only invitation does not grant admin' );
    is( scalar @{ maintainer_add_logs( $comm, $member_only ) },
        0, 'member-only invitation does not log maintainer_add' );
    is( scalar @sent_mail, 0, 'member-only invitation does not send admin mail' );

    my $ineligible_admin = temp_user();
    $ineligible_admin->set_prop( init_bdate => DateTime->now->subtract( years => 17 )->ymd );
    ok( $ineligible_admin->send_comm_invite( $comm, $admin, [ 'member', 'admin' ] ),
        'send member+admin invite to minor before explicit rating' );
    $comm->set_prop( adult_content => 'explicit' );
    @sent_mail = ();
    $rpc       = hover_accept( $ineligible_admin, $comm );
    LJ::start_request();
    ok( !$rpc->{success}, 'hover RPC rejects age-ineligible member+admin acceptance' );
    ok( !$ineligible_admin->member_of($comm),  'rejected acceptance does not grant membership' );
    ok( !$ineligible_admin->can_manage($comm), 'rejected acceptance does not grant admin' );
    ok( scalar( grep { $_->[0] == $comm->id } @{ $ineligible_admin->get_pending_invites } ),
        'rejected acceptance leaves invitation pending' );
    is( scalar @{ maintainer_add_logs( $comm, $ineligible_admin ) },
        0, 'rejected acceptance does not log maintainer_add' );
    is( scalar @sent_mail, 0, 'rejected acceptance does not send admin mail' );
    $comm->set_prop( adult_content => 'none' );
}

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
