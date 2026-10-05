#!/usr/bin/perl
#
# t/plack-settings-return.t
#
# Characterize notification return URLs used by the modern tracking form.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
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
use HTML::Form;
use URI;
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Controller::SettingsHub;
use DW::Request::Plack;
use LJ::Test qw(temp_user);
use LJ::Subscription::Pending;
plan skip_all => 'Settings integration requires a development server'
    unless $LJ::IS_DEV_SERVER;
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $owner   = temp_user();
my $journal = temp_user();
my $session = LJ::Session->create( $owner, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'settingsReturnProbe';

# The receiver derives its origin from the PSGI request, not $LJ::PROTOCOL.
{
    open my $input, '<', '/dev/null' or die "open /dev/null: $!";
    my $https = DW::Request::Plack->new(
        {
            REQUEST_METHOD    => 'GET',
            SCRIPT_NAME       => '',
            PATH_INFO         => '/',
            QUERY_STRING      => '',
            SERVER_NAME       => 'localhost',
            SERVER_PORT       => 8443,
            HTTP_HOST         => 'localhost:8443',
            'psgi.url_scheme' => 'https',
            'psgi.input'      => $input,
        }
    );
    local $LJ::PROTOCOL = 'http';
    ok(
        !defined DW::Controller::SettingsHub::_notification_return_url(
            $https, 'http://localhost:8443/return'
        ),
        'configured HTTP protocol cannot authorize an HTTP return for an HTTPS request'
    );
}

# Isolate notification delivery to the local Inbox; dev mail is not configured.
local @LJ::NOTIFY_TYPES = ('LJ::NotificationMethod::Inbox');
my $pending = LJ::Subscription::Pending->new(
    $owner,
    journal => $journal,
    event   => 'JournalNewEntry',
    method  => 'Inbox',
    flags   => LJ::Subscription::TRACKING
);
my $field = $pending->freeze;

sub persisted {
    my $fresh = LJ::load_userid( $owner->id, 1 );
    return [
        $fresh->find_subscriptions(
            event   => 'JournalNewEntry',
            journal => $journal,
            method  => 'Inbox',
            arg1    => 0,
            arg2    => 0
        )
    ];
}
test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub {
        my $request = shift;
        $request->header( Cookie => $cookie );
        return $send->($request);
    };
    my $res = $cb->(
        GET '/manage/tracking/user?journal=' . $journal->user,
        Referer => 'http://localhost/manage/profile'
    );
    my ($form) = grep { defined $_->find_input('post_to_settings_page') }
        HTML::Form->parse( $res->content, 'http://localhost/manage/tracking/user' );
    ok( $form && $form->find_input($field), 'tracking form offers the Inbox subscription' )
        or return;

    for my $input ( $form->inputs ) {
        $input->value(undef) if $input->type eq 'checkbox';
    }
    $form->value( $field, 1 );
    {
        no warnings 'redefine';
        local *LJ::User::max_subscriptions = sub { 0 };
        $res = $cb->( $form->click );
    }
    ok( !$res->header('Location'), 'notification quota failure stays on settings' );
    ( my $quota_text = $res->content ) =~ s/<[^>]+>//g;
    like(
        $quota_text,
        qr/reached your limit of .* active notifications/s,
        'quota error is visible rendered text'
    );
    is( scalar @{ persisted() }, 0, 'failed notification save leaves subscription absent' );

    $res = $cb->( $form->click );
    is( $res->code, 302, 'successful tracking save redirects' );
    is(
        $res->header('Location'),
        'http://localhost/manage/profile',
        'successful save returns to originating page'
    );
    my $saved = persisted();
    is( scalar @$saved, 1, 'successful tracking POST persists exactly one intended subscription' );
    ok( @$saved && $saved->[0]->active, 'saved subscription is active on fresh load' );

    $form->value( 'ret_url', '/some%2Fpath' );
    $res = $cb->( $form->click );
    is( $res->header('Location'), '/some%2Fpath', 'same-origin return keeps its raw URL bytes' );

    for my $untrusted (
        'https://offsite.invalid/landing',   '//offsite.invalid/landing',
        'http://attacker@localhost/landing', 'javascript:alert(1)',
        'http://localhost:8081/landing',     '/%5c%5coffsite.invalid/landing',
        )
    {
        $form->value( 'ret_url', $untrusted );
        $res = $cb->( $form->click );
        unlike( $res->content, qr/Invalid form/, "$untrusted reaches the receiver" );
        my $location = $res->header('Location');
        my $destination =
            defined $location
            ? URI->new_abs( $location, 'http://localhost/manage/settings/' )
            : undef;
        ok(
            !$destination || ( $destination->scheme eq 'http'
                && $destination->host eq 'localhost'
                && $destination->port == 80 ),
            "receiver refuses off-origin return URL $untrusted"
        );
    }
};
done_testing;
