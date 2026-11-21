# t/plack-notification-settings.t
#
# Notification settings save, delete and read-only access over HTTP.
#
# Authors:
#     SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Subscription::Pending;
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'notificationSettingsTest';
local $LJ::_T_EMAIL_NOTIFICATION      = 1;

my $owner  = temp_user();
my $viewer = temp_user();
my $target = temp_user();
$viewer->grant_priv( 'canview', 'subscriptions' );

my %tracked = (
    journal => $target,
    event   => 'JournalNewEntry',
    flags   => LJ::Subscription::TRACKING,
);
my $inbox = LJ::Subscription::Pending->new( $owner, %tracked, method => 'Inbox' );
my $email = LJ::Subscription::Pending->new( $owner, %tracked, method => 'Email' );
my $base  = 'http://localhost/manage/settings/notifications';
my $own   = "$base?as=" . $owner->user;

sub subscriptions {
    delete $owner->{_subscriptions};
    return $owner->find_subscriptions( journal => $target, event => $tracked{event} );
}

test_psgi $app, sub {
    my ($request) = @_;
    my $form = $request->( GET $own );
    is( $form->code, 200, 'owner can load notification settings' );
    like(
        $form->content,
        qr{css/components/inline-lists\.css},
        'Foundation tab list CSS is included'
    );
    like(
        $form->content,
        qr{css/pages/manage/notifications\.css},
        'Foundation notification settings CSS is included'
    );
    like( $form->content, qr{notifications\.js}, 'Foundation notifications script is included' );
    my ($auth) = $form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
    ok( $auth, 'the settings form has a session-bound token' );

    my @fields = ( $inbox->freeze => 1, $email->freeze => 1 );
    $request->( POST $own, [@fields] );
    is( scalar( subscriptions() ), 0, 'a request without a token cannot create a subscription' );

    my $saved = $request->( POST $own, [ @fields, lj_form_auth => $auth ] );
    is( $saved->code,              200, 'owner can submit changes' );
    is( scalar( subscriptions() ), 2,   'both Inbox and email subscriptions are saved' );

    my ($saved_inbox) = grep { $_->method eq 'LJ::NotificationMethod::Inbox' } subscriptions();
    ok( $saved_inbox, 'the tracked event has an Inbox subscription' );
    my $delete_id = $saved_inbox->id;

    $request->( GET "$own&deletesub_$delete_id=1" );
    is( scalar( subscriptions() ), 2, 'GET cannot delete tracking' );

    my $staff     = "$base?as=" . $viewer->user;
    my $inspected = $request->( GET "$staff&user=" . $owner->user );
    is( $inspected->code, 200, 'staff can inspect another account' );
    unlike( $inspected->content, qr/id="settings_form"/, 'staff view has no edit form' );

    my $staff_form = $request->( GET $staff );
    my ($staff_auth) = $staff_form->content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
    ok( $staff_auth, 'staff has a valid token for their own account' );
    $request->(
        POST "$staff&user=" . $owner->user,
        [ delete_subscription => $delete_id, lj_form_auth => $staff_auth ]
    );
    is( scalar( subscriptions() ), 2, 'staff cannot delete tracking for another account' );

    $request->( POST $own, [ delete_subscription => $delete_id, lj_form_auth => $auth ] );
    is( scalar( subscriptions() ), 0, 'owner deletion removes both delivery methods' );

    my $return_url = 'http://localhost/users/' . $target->user . '/';
    my $returned   = $request->( POST $own, [ lj_form_auth => $auth, ret_url => $return_url ] );
    is( $returned->code,               303,         'a tracking form can return to the journal' );
    is( $returned->header('Location'), $return_url, 'the journal return URL is preserved' );

    my $legacy     = 'http://localhost/manage/settings/?cat=notifications&as=' . $owner->user;
    my $legacy_get = $request->( GET "$legacy&page=2" );
    is( $legacy_get->code, 302, 'bookmarked settings link still works' );
    like(
        $legacy_get->header('Location'),
        qr{/manage/settings/notifications\?page=2\z},
        'bookmark preserves the tracking page number'
    );
    my $legacy_post = $request->( POST $legacy, [ lj_form_auth => $auth ] );
    is( $legacy_post->code, 307, 'old tracking forms can still send their POST body' );
    like(
        $legacy_post->header('Location'),
        qr{/manage/settings/notifications\z},
        'old tracking POST redirects to the Foundation route'
    );
};

done_testing;
