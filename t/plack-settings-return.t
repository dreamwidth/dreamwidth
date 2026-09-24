# Characterize notification return URLs used by the modern tracking form.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use HTML::Form;
use URI;
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
require DW::Controller::SettingsHub;
require DW::Request::Plack;
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

# The receiver must derive its origin from the actual PSGI request, not the
# deployment-wide protocol setting.  This is deliberately HTTPS while the
# development default below is HTTP.
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
    is( DW::Controller::SettingsHub::_notification_return_url( $https, '/return' ),
        '/return', 'relative return is resolved against the actual HTTPS request origin' );
    is(
        DW::Controller::SettingsHub::_notification_return_url(
            $https, 'https://localhost:8443/return'
        ),
        'https://localhost:8443/return',
        'same HTTPS host and port are accepted despite configured protocol mismatch'
    );
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
    is( $res->code, 200, 'modern tracking form renders' );
    my ($form) = grep { defined $_->find_input('post_to_settings_page') }
        HTML::Form->parse( $res->content, 'http://localhost/manage/tracking/user' );
    ok( $form, 'tracking form targets settings hub' ) or return;
    is(
        $form->value('ret_url'),
        'http://localhost/manage/profile',
        'validated return URL is carried in real form'
    );
    ok( $form->find_input($field), 'actual form contains requested Inbox subscription' ) or return;

    for my $input ( $form->inputs ) {
        $input->value(undef) if $input->type eq 'checkbox';
    }
    $form->value( $field, 1 );
    my $token = $form->value('lj_form_auth');
    is( scalar @{ persisted() }, 0, 'subscription starts absent' );
    $form->value( 'lj_form_auth', 'invalid' );
    $res = $cb->( $form->click );
    ok( !$res->header('Location'), 'invalid token cannot use the return redirect' );
    like( $res->content, qr/Invalid form/i, 'invalid tracking token has meaningful error' );
    is( scalar @{ persisted() }, 0, 'invalid token leaves subscription absent' );
    $form->value( 'lj_form_auth', $token );
    {
        no warnings 'redefine';
        local *LJ::User::max_subscriptions = sub { 0 };
        $res = $cb->( $form->click );
    }
    ok( !$res->header('Location'), 'notification validation failure stays on settings' );
    like(
        $res->content,
        qr/reached your limit of .* active notifications/s,
        'notification quota failure is visible instead of a redirect'
    );
    unlike(
        $res->content,
        qr/undef error|DieObject=|BML ERROR/,
        'validation response is not an exception banner'
    );
    unlike( $res->content, qr/<[?]errorbar/,
        'quota response contains no legacy BML errorbar token' );
    ( my $quota_text = $res->content ) =~ s/<[^>]+>//g;
    like(
        $quota_text,
        qr/reached your limit of .* active notifications/s,
        'quota error is visible rendered text, not inert legacy BML markup'
    );
    is( scalar @{ persisted() }, 0, 'failed notification save leaves subscription absent' );
    $res = $cb->( $form->click );
    is( $res->code, 302, 'successful tracking save retains legacy redirect status' );
    is(
        $res->header('Location'),
        'http://localhost/manage/profile',
        'successful save returns to originating page'
    );
    my $saved = persisted();
    is( scalar @$saved, 1, 'successful tracking POST persists exactly one intended subscription' );
    ok( @$saved && $saved->[0]->active, 'saved subscription is active on fresh load' );

    for my $accepted ( '/some%2Fpath', 'http://localhost/%2Fok', '/return?next=%2Ffolder' ) {
        $form->value( 'ret_url', $accepted );
        $res = $cb->( $form->click );
        is( $res->code, 302, "same-origin encoded slash return redirects: $accepted" );
        is( $res->header('Location'),
            $accepted, "same-origin encoded slash return preserves its raw URL bytes: $accepted" );
        is( scalar @{ persisted() },
            1, "accepted encoded slash return does not duplicate the subscription: $accepted" );
    }

    # The settings receiver owns this final validation, including URL forms
    # that browser-side callers normally never emit.
    for my $untrusted (
        'https://offsite.invalid/landing',   '//offsite.invalid/landing',
        'http://attacker@localhost/landing', 'javascript:alert(1)',
        'http://localhost:8081/landing',     '/%5c%5coffsite.invalid/landing',
        )
    {
        $form->value( 'ret_url', $untrusted );
        $res = $cb->( $form->click );
        unlike(
            $res->content,
            qr/Invalid form|undef error|DieObject=|BML ERROR/,
            'forged return URL reaches receiver with valid session and token'
        );
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
        is( scalar @{ persisted() },
            1, 'forged return URL does not duplicate the intended subscription' );
    }
};
done_testing;
