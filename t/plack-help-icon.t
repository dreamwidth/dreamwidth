#!/usr/bin/perl
# Characterizes LJ::Web::help_icon's dead "<?help ... help?>" tag, which
# never resolved from a native TT page (only the BML rendering engine's own
# macro understood it), reaching native TT pages via LJ::Widget::JournalTitles
# (a widget), DW::Controller::Manage::Profile (a controller), and
# LJ::Web::subscribe_interface (feeding the /manage/tracking and
# /manage/settings notifications pages), and proves the fix: help_icon now
# renders the same real help link help_icon_html already produces elsewhere
# (LJ::Talk.pm, DW::Controller::EditIcons already use it correctly).
#
# help_icon only emits anything at all once %LJ::HELPURL has the relevant
# topic key set; this dev config has none configured, so each subtest sets
# the key it needs locally to make the (pre-fix) literal actually reproduce.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;

use Test::More;
use HTTP::Request::Common qw(GET);
use Plack::Test;

BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Plack;
use LJ::Test qw(temp_user);
use LJ::Widget::JournalTitles;
use LJ::Subscription::Pending;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $u = temp_user();
$u->update_self( { status => 'A' } );

local $LJ::HELPURL{journal_titles} = 'http://example.com/help/journal_titles';
local $LJ::HELPURL{upic_keywords}  = 'http://example.com/help/upic_keywords';

subtest 'LJ::Widget::JournalTitles (widget): help_icon renders a real link' => sub {
    DW::Request->reset;
    DW::Request::Plack->new(
        {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => '/',
            QUERY_STRING      => '',
            'psgi.url_scheme' => 'http'
        }
    );
    LJ::set_remote($u);
    my $html = LJ::Widget::JournalTitles->render;
    unlike( $html, qr/<\?help/, 'no literal "<?help ...?>" BML tag reaches the rendered widget' );
    like( $html, qr/class="helplink"/, 'a real help_icon_html-style link renders instead' );
    like(
        $html,
        qr{http://example\.com/help/journal_titles},
        'the configured help URL for this topic is used'
    );
};

subtest '/manage/profile (controller): help_icon renders a real link' => sub {
    my $session = LJ::Session->create( $u, nolog => 1 );
    my $cookie =
          'ljmastersession='
        . $session->master_cookie_string
        . '; ljloggedin='
        . $session->loggedin_cookie_string;

    test_psgi $app, sub {
        my $cb  = shift;
        my $req = GET 'http://localhost/manage/profile';
        $req->header( Cookie => $cookie );
        my $res = $cb->($req);
        is( $res->code, 200, '/manage/profile renders' );
        unlike( $res->content, qr/<\?help/,
            'no literal "<?help ...?>" BML tag reaches the rendered page' );
        like( $res->content, qr/class="helplink"/,
            'a real help_icon_html-style link renders instead' );
        like(
            $res->content,
            qr{http://example\.com/help/upic_keywords},
            'the configured help URL for this topic is used'
        );
    };
};

# LJ::Web::subscribe_interface (Web.pm:2186) calls LJ::help_icon($notify_class
# ->help_url) for each notification method class, gated on that class having a
# help_url at all. No in-tree LJ::NotificationMethod subclass currently
# overrides help_url (the base class returns undef), so this call is reachable
# code but not exercised by anything in this tree today -- force it locally,
# on the one non-Inbox method that exists (LJ::NotificationMethod::Email; the
# Inbox method is always filtered out of subscribe_interface's own loop), to
# prove the fix through /manage/tracking/user, one of the two controllers that
# embed subscribe_interface's shared output (/manage/settings's notifications
# category embeds the same call and is covered generically elsewhere).
local $LJ::HELPURL{notify_email_help} = 'http://example.com/help/notify_email';
no warnings 'redefine';
local *LJ::NotificationMethod::Email::help_url = sub { return 'notify_email_help'; };

subtest
    '/manage/tracking/user (controller, via subscribe_interface): help_icon renders a real link' =>
    sub {
    my $owner   = temp_user();
    my $journal = temp_user();
    $journal->update_self( { status => 'A' } );

    LJ::Subscription::Pending->new(
        $owner,
        journal => $journal,
        event   => 'JournalNewEntry',
        method  => 'Email',
        flags   => LJ::Subscription::TRACKING
    )->commit;

    my $session = LJ::Session->create( $owner, nolog => 1 );
    my $cookie =
          'ljmastersession='
        . $session->master_cookie_string
        . '; ljloggedin='
        . $session->loggedin_cookie_string;

    test_psgi $app, sub {
        my $cb  = shift;
        my $req = GET( 'http://localhost/manage/tracking/user?journal=' . $journal->user );
        $req->header( Cookie => $cookie );
        my $res = $cb->($req);
        is( $res->code, 200, '/manage/tracking/user renders' );
        unlike( $res->content, qr/<\?help/,
            'no literal "<?help ...?>" BML tag reaches the rendered tracking page' );
        like( $res->content, qr/class="helplink"/,
            'a real help_icon_html-style link renders instead' );
        like(
            $res->content,
            qr{http://example\.com/help/notify_email},
            'the configured help URL for the notification method is used'
        );
    };
    };

done_testing;
