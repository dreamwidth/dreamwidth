#!/usr/bin/perl
# Regression coverage for tracking strings included by the native settings hub.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use lib "$ENV{LJHOME}/cgi-bin";
use HTTP::Request::Common;
use Plack::Test;
use DW::Request;
use DW::Request::Plack;
use DW::Template;
use LJ::Lang;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub cookie_for {
    my ($user) = @_;
    my $session = LJ::Session->create( $user, nolog => 1 );
    return
          'ljmastersession='
        . $session->master_cookie_string
        . '; ljloggedin='
        . $session->loggedin_cookie_string;
}

local @LJ::NOTIFY_TYPES = ('LJ::NotificationMethod::Inbox');
my $user   = temp_user();
my $cookie = cookie_for($user);
test_psgi $app, sub {
    my $send = shift;
    my $res  = $send->( GET '/manage/settings/?cat=notifications', Cookie => $cookie );
    is( $res->code, 200, 'notification settings render through the native hub' );
    unlike(
        $res->content,
        qr/\[missing string /,
        'notification body has no missing inherited settings-hub translation key'
    );
    like(
        $res->content,
        qr/Delete all inactive tracked items/,
        'notification body resolves the tracking delete label from its own text file'
    );
    like(
        $res->content,
        qr/Are you sure you want to delete all inactive tracked items\?/,
        'notification confirmation text is rendered from the tracking scope'
    );
    like(
        $res->content,
        qr/window[.]SettingsConfirmMsg\s*=/,
        'notification form receives the server-emitted localized dirty-form confirmation'
    );

    $res = $send->( GET '/manage/settings/?cat=privacy', Cookie => $cookie );
    is( $res->code, 200, 'privacy settings render through the native hub' );
    like(
        $res->content,
        qr/window[.]SettingsConfirmMsg\s*=/,
        'ordinary settings form receives the server-emitted localized dirty-form confirmation'
    );
};

# The hub renders this fragment by INCLUDE, so exercise its explicit keys with
# a distinct native request getter rather than relying on the parent scope.
DW::Request->reset;
open my $input, '<', \( my $body = '' ) or die $!;
DW::Request->get(
    plack_env => {
        REQUEST_METHOD    => 'GET',
        PATH_INFO         => '/manage/settings/',
        QUERY_STRING      => '',
        SERVER_NAME       => 'localhost',
        SERVER_PORT       => 80,
        HTTP_HOST         => 'localhost',
        'psgi.version'    => [ 1, 1 ],
        'psgi.url_scheme' => 'http',
        'psgi.input'      => $input,
        'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh },
    },
);
my @calls;
LJ::Lang::set_request_context(
    lang   => 'marker',
    getter => sub {
        my ( $lang, $code ) = @_;
        push @calls, [ $lang, $code ];
        return "MARKER:$code";
    },
);
my $fragment = DW::Template->template_string(
    'tracking/settings-interface.tt',
    {
        has_admin_form      => 0,
        has_user_form       => 1,
        post_action         => '/manage/settings/?cat=notifications',
        viewing_self        => 1,
        get_args            => {},
        subscribe_interface => '',
        delete_base_url     => '/manage/settings/?cat=notifications',
    }
);
like(
    $fragment,
    qr/MARKER:\/tracking\/settings-interface[.]tt[.]btn[.]deleteinactive/,
    'tracking fragment sends its delete label through the explicit native full key'
);
like(
    $fragment,
    qr/MARKER:\/tracking\/settings-interface[.]tt[.]confirm[.]deleteinactive/,
    'tracking fragment sends its escaped confirmation through the explicit native full key'
);
is_deeply(
    [ map { $_->[1] } grep { $_->[1] =~ m!\A/tracking/settings-interface[.]tt[.]! } @calls ],
    [
        '/tracking/settings-interface.tt.btn.deleteinactive',
        '/tracking/settings-interface.tt.confirm.deleteinactive',
        '/tracking/settings-interface.tt.btn.save',
        '/tracking/settings-interface.tt.btn.save',
    ],
    'included tracking controls no longer inherit the settings hub request scope'
);
DW::Request->reset;

done_testing;
