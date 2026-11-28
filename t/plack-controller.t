#!/usr/bin/perl
# t/plack-controller.t
#
# Tests shared controller behavior through the full Plack stack.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2025 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use v5.10;

use Test::More;
use Digest::SHA qw(hmac_sha256_hex);
use HTTP::Request::Common;
use Plack::Test;

BEGIN {
    $LJ::_T_CONFIG = 1;
    require "$ENV{LJHOME}/cgi-bin/ljlib.pl";
}

use DW::API::Key;
use DW::OAuth::Access;
use DW::OAuth::Consumer;
use DW::OAuth::Request;
use DW::Shop;
use DW::Shop::Cart;
use LJ::JSON;
use LJ::Session;
use LJ::Test qw(temp_user);

# Load the Plack app
my $app_file = "$ENV{LJHOME}/app.psgi";
my $app      = do $app_file;
die "Failed to load app.psgi: $@" if $@;
die "app.psgi did not return a code reference" unless $app && ref $app eq 'CODE';

# Test: GET /login returns 200 with login form HTML
test_psgi $app, sub {
    my $cb  = shift;
    my $res = $cb->( GET "http://localhost/login?skin=global" );

    is( $res->code, 200, "GET /login returns 200" );
    like( $res->content, qr/<form/i, "Response contains a login form" );

    # /login must be marked no-cache: the form embeds a uniq-bound form_auth
    # token, so a shared cache serving one user's page to another would break
    # login with "Invalid form submission".
    like( $res->header('Cache-Control'), qr/no-cache/, "GET /login is marked no-cache" );
};

my $visible   = temp_user();
my $deleted   = temp_user();
my $suspended = temp_user();
$deleted->update_self(   { statusvis => 'D' } );
$suspended->update_self( { statusvis => 'S' } );

my $deleted_session   = LJ::Session->create($deleted);
my $suspended_session = LJ::Session->create($suspended);

sub loggedin_cookie {
    my ($session) = @_;
    return 'ljloggedin=' . $session->loggedin_cookie_string;
}

sub master_cookies {
    my ($session) = @_;
    return 'ljmastersession=' . $session->master_cookie_string . '; ' . loggedin_cookie($session);
}

test_psgi $app, sub {
    my $cb   = shift;
    my $base = 'http://localhost';
    local $LJ::IS_DEV_SERVER = 1;

    is( $cb->( GET "$base/tools/search" )->code, 200, 'search still allows anonymous visitors' );
    is( $cb->( GET "$base/tools/search?as=" . $visible->user )->code,
        200, 'search allows a visible account' );
    is( $cb->( GET "$base/manage/index" )->code,
        302, 'account management still redirects anonymous visitors to login' );

    for my $account ( $deleted, $suspended ) {
        my $query  = '?as=' . $account->user;
        my $status = $account->statusvis;
        is( $cb->( GET "$base/tools/search$query" )->code,
            403, "search rejects a signed-in account with status $status" );
        is( $cb->( GET "$base/manage/index$query" )->code,
            403, "account management rejects a signed-in account with status $status" );
        for my $path ( '/accountstatus', '/logout', '/support/submit' ) {
            is( $cb->( GET "$base$path$query" )->code,
                200, "$path remains available with account status $status" );
        }
    }
};

subtest 'domain session recovery' => sub {
    local $LJ::DOMAIN      = 'example.test';
    local $LJ::DOMAIN_WEB  = 'www.example.test';
    local $LJ::USER_DOMAIN = 'example.test';
    local $LJ::SITEROOT    = 'https://www.example.test';
    local $LJ::PROTOCOL    = 'https';

    my $journal_host = $visible->user =~ tr/_/-/r;
    my $journal      = "https://$journal_host.$LJ::USER_DOMAIN";
    my $destination  = "$journal/entry/new";

    test_psgi $app, sub {
        my $cb = shift;

        for my $session ( $deleted_session, $suspended_session ) {
            subtest 'account status ' . $session->owner->statusvis => sub {
                my $master = master_cookies($session);
                my $logged = loggedin_cookie($session);

                is( $cb->( GET "$LJ::SITEROOT/tools/search", Cookie => $master )->code,
                    403, 'the account still cannot use a restricted controller' );

                my $bounce = $cb->( GET $destination, Cookie => $logged );
                is( $bounce->code, 303, 'missing domain cookie starts recovery' );
                my $recovery_url = $bounce->header('Location') // '';
                like(
                    $recovery_url,
                    qr{^\Q$LJ::SITEROOT\E/misc/get_domain_session\?},
                    'recovery goes to the main site'
                );
                return unless $recovery_url;

                my $handoff = $cb->( GET $recovery_url, Cookie => $master );
                is( $handoff->code, 303, 'master session can recover a domain cookie' );
                my $helper_url = $handoff->header('Location') // '';
                like(
                    $helper_url,
                    qr{^\Q$journal\E/__setdomsess\?},
                    'handoff goes to the journal cookie endpoint'
                );
                return unless $helper_url;

                my $helper = $cb->( GET $helper_url, Cookie => $logged );
                is( $helper->header('Location'), $destination, 'returns to original journal URL' );
                my ($domain_cookie) =
                    map { /^(ljdomsess\.[^=]+=[^;]+)/ } $helper->headers->header('Set-Cookie');
                ok( $domain_cookie, 'journal issued a domain session cookie' );
                if ($domain_cookie) {
                    my $result    = $cb->( GET $destination, Cookie => "$logged; $domain_cookie" );
                    my $entry_url = "$LJ::SITEROOT/entry/$journal_host/new";
                    is( $result->header('Location'), $entry_url,
                        'recovered domain session reaches the journal route without another bounce'
                    );
                    is( $cb->( GET $entry_url, Cookie => $master )->code,
                        403, 'the destination controller still denies the account' );
                }
            };
        }
    };
};

subtest 'account and support self-service' => sub {
    my $base             = 'http://localhost';
    my $deleted_cookie   = master_cookies($deleted_session);
    my $suspended_cookie = master_cookies($suspended_session);

    $deleted->update_self( { status => 'T' } );
    my $action = LJ::register_authaction( $deleted->id, 'validateemail', $deleted->email_raw );

    test_psgi $app, sub {
        my $cb = shift;

        my $change = $cb->( GET "$base/changeemail", Cookie => $deleted_cookie );
        is( $change->code, 200, 'deleted account can reach email maintenance' );
        ok( $change->content =~ qr{<form action='[^']*/changeemail'},
            'email change form is available' );

        $change = $cb->( GET "$base/changeemail", Cookie => $suspended_cookie );
        ok(
            $change->content =~ qr{while your account is suspended},
            'suspended account still cannot change its email'
        );

        $cb->( GET "$base/register?$action->{aaid}.invalid", Cookie => $deleted_cookie );
        is( LJ::load_userid( $deleted->id )->email_status,
            'T', 'invalid code does not verify email' );

        my $confirm = $cb->( GET "$base/confirm/$action->{aaid}.$action->{authcode}" );
        is( $confirm->code, 303, 'email link redirects to verification' );
        my $verify = $cb->( GET $base . $confirm->header('Location'), Cookie => $deleted_cookie );
        is( $verify->code, 200, 'deleted account can use its email verification link' );
        is( LJ::load_userid( $deleted->id )->email_status, 'A', 'valid code verifies email' );

        $deleted->set_prop( opt_getselfsupport => 1 );
        my $support = "$base/support/changenotify";
        is( $cb->( GET $support )->code, 302, 'support preferences still require login' );

        $cb->( POST $support, Cookie => $deleted_cookie, Content => [ opt_getselfsupport => 0 ] );
        is( LJ::load_userid( $deleted->id )->prop('opt_getselfsupport'),
            1, 'support preferences do not change without form authentication' );

        my $form = $cb->( GET $support, Cookie => $deleted_cookie );
        is( $form->code, 200, 'deleted account can access support preferences' );
        my ($fields) = $form->content =~ m{<form method='post' action='changenotify'>(.*?)</form>}s;
        my ($token)  = ( $fields // '' ) =~ /name="lj_form_auth" value="([^"]+)"/;
        ok( $token, 'support preferences include a form token' );
        if ($token) {
            my @categories = $fields =~ /name=["'](spcatid_\d+)["']/g;
            $cb->(
                POST $support,
                Cookie  => $deleted_cookie,
                Content => [ lj_form_auth => $token, map { $_ => 'off' } @categories ]
            );
            is( LJ::load_userid( $deleted->id )->prop('opt_getselfsupport') || 0,
                0, 'deleted account can turn off its support notifications' );
        }
    };
};

subtest 'invisible accounts can revoke their own OAuth authorizations' => sub {
    local @LJ::SECRETS{qw(oauth_consumer oauth_request oauth_access)} =
        ( 'test-consumer', 'test-request', 'test-access' );

    my $base = 'http://localhost';
    my ( $application, $other_application ) = map {
        my $consumer = DW::OAuth::Consumer->new(
            u       => $visible,
            name    => $_,
            website => 'https://example.test/'
        );
        $consumer->approved(1);
        $consumer->active(1);
        $consumer->save or die 'Could not save test OAuth consumer';
        $consumer;
    } ( 'Test OAuth application', 'Other OAuth application' );

    for my $grant (
        [ $application,       $deleted ],
        [ $application,       $suspended ],
        [ $other_application, $visible ]
        )
    {
        my ( $consumer, $account ) = @$grant;
        my $request = DW::OAuth::Request->new( $consumer, userid => $account->id );
        DW::OAuth::Access->new($request) or die 'Could not create test OAuth authorization';
        $request->delete;
    }

    my $detail_path = '/oauth/token/' . $application->id;
    my $other_path  = '/oauth/token/' . $other_application->id;
    my $other_user  = '?user=' . $visible->user;

    test_psgi $app, sub {
        my $cb = shift;

        for my $session ( $deleted_session, $suspended_session ) {
            my $account = $session->owner;
            subtest 'account status ' . $account->statusvis => sub {
                my $cookie = master_cookies($session);

                my $history = $cb->( GET "$base/manage/logins", Cookie => $cookie );
                is( $history->code, 200, 'Login History remains available' );
                like( $history->content, qr{href="/oauth/"}, 'Login History links to the list' );
                like( $history->content, qr{href="\Q$detail_path\E"},
                    'Login History links to the grant' );

                my $list = $cb->( GET "$base/oauth/$other_user", Cookie => $cookie );
                is( $list->code, 200, 'OAuth list remains available' );
                ok(
                    $list->content =~ qr{\Q$detail_path\E["']},
                    'OAuth list shows the grant for this account'
                );
                unlike( $list->content, qr{\Q$other_path\E["']},
                    'OAuth list does not expose grants for another account' );

                my $detail = $cb->( GET "$base$detail_path", Cookie => $cookie );
                is( $detail->code, 200, 'OAuth detail remains available' );
                is( $cb->( GET "$base$other_path$other_user", Cookie => $cookie )->code,
                    404, 'OAuth detail does not expose a grant for another account' );
                my ($fields) = $detail->content =~
                    m{<form\b[^>]*\Q$detail_path/deauthorize\E[^>]*>(.*?)</form>}is;
                my ($token) = ( $fields // '' ) =~ /name="lj_form_auth" value="([^"]+)"/;
                ok( $token, 'the revoke form includes a real form token' );

                my $invalid = $cb->(
                    POST "$base$detail_path/deauthorize",
                    Cookie  => $cookie,
                    Content => [ lj_form_auth => 'invalid' ]
                );
                ok(
                    $invalid->content =~ qr/Invalid form submission/i,
                    'invalid form authentication is rejected'
                );
                ok(
                    DW::OAuth::Access->from_consumer( $account, $application->id ),
                    'invalid form authentication leaves the grant in place'
                );

                my @form = ( lj_form_auth => ( $token // '' ) );
                is(
                    $cb->(
                        POST "$base$other_path/deauthorize$other_user",
                        Cookie  => $cookie,
                        Content => \@form
                    )->code,
                    404,
                    'valid form authentication cannot revoke a grant for another account'
                );
                ok( DW::OAuth::Access->from_consumer( $visible, $other_application->id ),
                    'the other account keeps its grant' );

                my $revoke = $cb->(
                    POST "$base$detail_path/deauthorize",
                    Cookie  => $cookie,
                    Content => \@form
                );
                is( $revoke->header('Location'),
                    '/oauth/', 'owner returns to the OAuth list after revocation' );
                ok( !DW::OAuth::Access->from_consumer( $account, $application->id ),
                    'the grant is removed for its owner' );
            };
        }
    };

    $application->delete;
    $other_application->delete;
};

subtest 'deleted account can export its journal' => sub {
    my $account = temp_user();
    my $entry   = $account->t_post_fake_entry( subject => 'Entry saved before deletion' );
    $entry->t_enter_comment( u => $account, body => 'Comment saved before deletion' );
    my ( $year, $month ) = split /-/, $entry->eventtime_mysql, 3;
    $account->update_self( { statusvis => 'D' } );
    my $cookie = master_cookies( LJ::Session->create($account) );
    my $base   = 'http://localhost';

    test_psgi $app, sub {
        my $cb = shift;

        my $form = $cb->( GET "$base/export", Cookie => $cookie );
        is( $form->code, 200, 'deleted account can open the export form' );
        my ( $action, $fields ) =
            $form->content =~ m{<form action='(export_do[^']*)'[^>]*>(.*?)</form>}s;
        my ($token) = ( $fields // '' ) =~ /name="lj_form_auth" value="([^"]+)"/;
        ok( $action && $token, 'export form supplies a destination and form token' );

        my @fields  = ( format => 'csv', year => $year, month => $month, field_subject => 1 );
        my $url     = "$base/" . ( $action // 'export_do' );
        my $invalid = $cb->( POST $url, Cookie => $cookie, Content => \@fields );
        ok(
            !$invalid->header('Content-Disposition'),
            'export POST still requires form authentication'
        );

        my $download = $cb->(
            POST $url,
            Cookie  => $cookie,
            Content => [ @fields, lj_form_auth => ( $token // '' ) ]
        );
        is( $download->code, 200, 'deleted account can download entries' );
        like( $download->header('Content-Disposition') // '',
            qr/^attachment;.*\.csv$/, 'entries are returned as a CSV attachment' );
        like( $download->content, qr/Entry saved before deletion/, 'CSV contains the saved entry' );

        my $comments_url = "$base/export_comments?get=comment_body";
        is( $cb->( GET $comments_url )->code, 302, 'comment export still requires login' );
        my $comments = $cb->( GET $comments_url, Cookie => $cookie );
        is( $comments->code,         200,        'deleted account can download comments' );
        is( $comments->content_type, 'text/xml', 'comments are returned as XML' );
        like(
            $comments->content,
            qr{<body>Comment saved before deletion</body>},
            'XML contains the saved comment'
        );
    };
};

subtest 'invisible accounts can follow up on a Support History search' => sub {
    local @LJ::MANTICORE = ( '127.0.0.1', 9312, 9306 );
    my $history_url = 'http://localhost/support/history';

    test_psgi $app, sub {
        my $cb = shift;

        for my $status ( 'D', 'S' ) {
            my $account = temp_user();
            $account->grant_priv('supporthelp');
            $account->update_self( { statusvis => $status } );
            my $cookie = master_cookies( LJ::Session->create($account) );

            my $form = $cb->( GET $history_url, Cookie => $cookie );
            my ($token) = $form->content =~ /name="lj_form_auth" value="([^"]+)"/;
            my $search = $cb->(
                POST $history_url,
                Cookie  => $cookie,
                Content => [ fulltext => ' ', lj_form_auth => ( $token // '' ) ]
            );
            is( $search->code, 200, "account status $status can start a history search" );
            like(
                $search->content,
                qr/Please specify a search string/,
                'initial search reaches query validation'
            );
            my ( $action, $fields ) =
                $search->content =~ m{<form method="post" action="([^"]+)"[^>]*>(.*?)</form>}s;
            my ($search_token) = ( $fields // '' ) =~ /name="lj_form_auth" value="([^"]+)"/;
            ok( $action && $search_token, 'search response supplies a follow-up form' );

            my $page = $cb->(
                POST 'http://localhost' . ( $action // '/support/search' ),
                Cookie => $cookie,
                Content =>
                    [ query => 'history', offset => 1020, lj_form_auth => ( $search_token // '' ) ]
            );
            is( $page->code, 200, "account status $status can submit a follow-up search page" );
            like(
                $page->content,
                qr/Offset must be between 0 and 1000/,
                'follow-up reaches pagination validation'
            );
        }
    };
};

subtest 'deleted account can manage eligible old email addresses' => sub {
    my $account = temp_user();
    $account->update_self( { statusvis => 'D', status => 'T' } );
    my $cookie = master_cookies( LJ::Session->create($account) );
    my $url    = 'http://localhost/tools/emailmanage';
    my $email  = 'old-address@example.test';
    my $time   = LJ::mysql_time( time() - 183 * 86400, 1 );
    my $dbh    = LJ::get_db_writer();
    $dbh->do(
'INSERT INTO infohistory (userid, what, timechange, oldvalue, other) VALUES (?, ?, ?, ?, ?)',
        undef, $account->id, 'email', $time, $email, ''
    );
    my $history_type = sub {
        return $dbh->selectrow_array( 'SELECT what FROM infohistory WHERE userid=? AND oldvalue=?',
            undef, $account->id, $email );
    };

    test_psgi $app, sub {
        my $cb = shift;
        is( $cb->( GET $url )->code, 302, 'old-address management still requires login' );

        $cb->( POST $url, Cookie => $cookie, Content => [ "$email-$time" => 1 ] );
        is( $history_type->(), 'email', 'unverified account cannot remove old addresses' );

        $account->update_self( { status => 'A' } );
        my $other = master_cookies( LJ::Session->create($visible) );
        $cb->(
            POST "$url?authas=" . $account->user,
            Cookie  => $other,
            Content => [ "$email-$time" => 1 ]
        );
        is( $history_type->(), 'email', 'another user cannot remove the old address' );

        my $form = $cb->( GET $url, Cookie => $cookie );
        is( $form->code, 200, 'verified deleted account can review old addresses' );
        like( $form->content, qr/\Q$email\E/, 'old address is listed' );
        my ($token) = $form->content =~ /name="lj_form_auth" value="([^"]+)"/;
        $cb->(
            POST $url,
            Cookie  => $cookie,
            Content => [ lj_form_auth => ( $token // '' ), "$email-$time" => 1 ]
        );
        is( $history_type->(), 'emaildeleted', 'eligible old address is removed from history' );
    };
};

subtest 'API account visibility' => sub {
    my $base   = 'http://localhost/api/v1';
    my $cookie = master_cookies($deleted_session);
    my $key    = DW::API::Key->new_for_user($visible)->hash;
    my $tags   = "$base/journals/" . $visible->user . '/tags';

    test_psgi $app, sub {
        my $cb = shift;

        is( $cb->( GET $tags, Cookie => $cookie, Authorization => "Bearer $key" )->code,
            200, 'REST authenticates with the visible bearer principal, not the cookie account' );

        my $no_key = $cb->( GET $tags, Cookie => $cookie );
        is( $no_key->code, 401, 'cookie session cannot replace the bearer key' );
        is( $no_key->content_type, 'application/json', 'REST authentication error is JSON' );
        my $no_key_body = eval { from_json( $no_key->content ) };
        is_deeply(
            $no_key_body,
            { success => 0, error => 'Missing or invalid API key' },
            'REST authentication error body'
        );

        for my $endpoint (qw(new edit)) {
            my $response = $cb->( POST "$base/file/$endpoint", Cookie => $cookie );
            is( $response->code, 403, "media $endpoint denies the invisible cookie account" );
            is( $response->content_type, 'application/json', "media $endpoint denial is JSON" );
            my $body = eval { from_json( $response->content ) } // {};
            is( $body->{success}, 0, "media $endpoint reports failure" );
            like( $body->{error}, qr/account is not active/,
                "media $endpoint explains the denial" );
        }
    };
};

subtest 'Stripe webhook response handling' => sub {
    local $LJ::DISABLED{payments}  = 0;
    local $LJ::DOMAIN_SHOP         = 'localhost';
    local $LJ::STRIPE{webhook_key} = 'test-webhook-key';

    my $url       = 'http://localhost/shop/stripe-webhook';
    my $event     = to_json( { type => 'test.unsupported' } );
    my $timestamp = time();
    my $signature = hmac_sha256_hex( "$timestamp.$event", $LJ::STRIPE{webhook_key} );

    test_psgi $app, sub {
        my $cb     = shift;
        my $denied = $cb->(
            POST $url,
            Cookie             => master_cookies($deleted_session),
            'Stripe-Signature' => "t=$timestamp,v1=$signature",
            Content_Type       => 'application/json',
            Content            => $event
        );
        is( $denied->code, 403, 'webhook preserves the controller denial status' );
        is( $denied->content_type, 'application/json', 'webhook denial is JSON' );
        my $body = eval { from_json( $denied->content ) } // {};
        is( $body->{success}, 0, 'webhook returns one JSON failure response' );
        like( $body->{error}, qr/account is not active/, 'webhook preserves the controller error' );

        my $invalid = $cb->(
            POST $url,
            'Stripe-Signature' => "t=$timestamp,v1=invalid",
            Content_Type       => 'application/json',
            Content            => $event
        );
        is( $invalid->code, 400, 'cookieless webhook rejects an invalid signature' );
        like( $invalid->content, qr/Invalid webhook signature/, 'signature failure is reported' );

        my $signed = $cb->(
            POST $url,
            'Stripe-Signature' => "t=$timestamp,v1=$signature",
            Content_Type       => 'application/json',
            Content            => $event
        );
        is( $signed->code, 400, 'signed cookieless webhook rejects an unsupported event' );
        like( $signed->content, qr/Unsupported event/, 'signed event reaches the Stripe engine' );
    };
};

subtest 'Stripe retries a completed checkout when payments are disabled' => sub {
    local $LJ::DISABLED{payments}         = 1;
    local $LJ::DOMAIN_SHOP                = 'localhost';
    local $LJ::STRIPE{webhook_key}        = 'test-webhook-key';
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = LJ::UniqCookie->generate_uniq_ident;

    my $cart = DW::Shop::Cart->new_cart($visible);
    $cart->state($DW::Shop::STATE_PEND_PAID);

    my $event = to_json(
        {
            type => 'checkout.session.completed',
            data => { object => { client_reference_id => $cart->id } },
        }
    );
    my $timestamp = time();
    my $signature = hmac_sha256_hex( "$timestamp.$event", $LJ::STRIPE{webhook_key} );
    my $request   = POST 'http://localhost/shop/stripe-webhook',
        'Stripe-Signature' => "t=$timestamp,v1=$signature",
        Content_Type       => 'application/json',
        Content            => $event;

    test_psgi $app, sub {
        my $cb = shift;

        is( $cb->( $request->clone )->code, 503, 'disabled payments request a retry' );
        is( DW::Shop::Cart->get_from_cartid( $cart->id )->state,
            $DW::Shop::STATE_PEND_PAID, 'disabled payments leave the order pending' );

        local $LJ::DISABLED{payments} = 0;
        is( $cb->( $request->clone )->code, 200, 'retry succeeds when payments resume' );
        is( DW::Shop::Cart->get_from_cartid( $cart->id )->state,
            $DW::Shop::STATE_PAID, 'retry marks the order paid' );
    };
};

done_testing;
