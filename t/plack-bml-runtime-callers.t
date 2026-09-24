#!/usr/bin/perl
# Characterizes ordinary BML runtime callers converted to their DW::Request
# or native equivalents (BML graduation package W5). Confirms output is
# unchanged for callers the BML::* shim already served correctly under
# Plack, and confirms correct output for callers the shim never served
# correctly outside an actively-rendering .bml page.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;

use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use DW::RenameToken;
use DW::Request::Standard;
use LJ::Event::SecurityAttributeChanged;
use LJ::Hooks;
use LJ::Test qw(temp_user);

plan skip_all => 'BML runtime caller characterization requires a development server'
    unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

subtest 'LJ::User::redirect_rename uses DW::Request, not the no-op BML::redirect' => sub {
    my $u            = temp_user();
    my $fromusername = $u->user;
    my $tousername   = $fromusername . "_renameto";
    ok(
        $u->rename(
            $tousername,
            token    => DW::RenameToken->create_token( ownerid => $u->id ),
            redirect => 1
        ),
        'rename with redirect succeeds'
    );
    my $orig_u = LJ::load_user($fromusername);
    ok( $orig_u->is_redirect, 'original account is now a redirect stub' );

    DW::Request->reset;
    my $r = DW::Request::Standard->new( GET 'http://localhost/foo' );
    $r->header_in( Host => 'localhost' );

    my $status = $orig_u->redirect_rename('/bar');
    is( $status, $r->REDIRECT, 'redirect_rename returns a real redirect status' );
    is(
        $r->header_out('Location'),
        $orig_u->get_renamed_user->journal_base . '/bar',
        'redirect_rename sets Location to the renamed-to journal, plus the given URI'
    );
    DW::Request->reset;
};

subtest 'LJ::User::_logout_common no longer depends on BML::set_scheme' => sub {
    my $u = temp_user();
    $u->update_self( { status => 'A' } );
    my $session = LJ::Session->create( $u, nolog => 1 );
    my $sessid  = $session->id;
    ok( $session, 'session created' );

    DW::Request->reset;
    my $r = DW::Request::Standard->new( GET 'http://localhost/logout' );
    $r->header_in( Host => 'localhost' );

    ok( eval { $u->logout; 1 }, 'logout does not die without an active BML render' )
        or diag("logout died: $@");
    ok( !LJ::Session->instance( $u, $sessid ), 'session no longer resolves after logout' );
    DW::Request->reset;
};

subtest 'DW::User::Rename logs the real request IP via LJ::get_remote_ip' => sub {
    my $u = temp_user();

    DW::Request->reset;
    my $r = DW::Request::Standard->new( GET 'http://localhost/rename' );
    $r->header_in( Host => 'localhost' );

    my @captured;
    no warnings qw(redefine once);
    local *LJ::Event::SecurityAttributeChanged::new = sub {
        my ( $class, $u, $opts ) = @_;
        push @captured, $opts;
        return bless {}, $class;
    };
    local *LJ::Event::SecurityAttributeChanged::fire = sub { return 1; };

    ok(
        $u->rename(
            $u->user . "_renameto",
            token => DW::RenameToken->create_token( ownerid => $u->id ),
        ),
        'rename succeeds'
    );
    is( scalar @captured, 1, 'account_renamed notification fired exactly once' );
    is( $captured[0]->{ip},
        '127.0.0.100', 'notification carries the real request IP, not [unknown]' );
    DW::Request->reset;
};

subtest 'DW::Hooks::Changelog uses LJ::get_remote_ip, not the crash-prone BML::get_remote_ip' =>
    sub {
    local %LJ::CHANGELOG = (
        enabled         => 1,
        community       => 'changelog_test_comm',
        allowed_posters => ['changelog_test_poster'],
        allowed_ips     => ['127.0.0.100'],
    );

    DW::Request->reset;
    my $r = DW::Request::Standard->new( GET 'http://localhost/interface/xmlrpc' );
    $r->header_in( Host => 'localhost' );

    ok(
        eval {
            LJ::Hooks::run_hook(
                'post_noauth',
                {
                    usejournal => 'changelog_test_comm',
                    username   => 'changelog_test_poster',
                }
            );
            1;
        },
        'post_noauth hook does not die when called from a native request context'
    ) or diag("post_noauth died: $@");
    ok(
        LJ::Hooks::run_hook(
            'post_noauth',
            {
                usejournal => 'changelog_test_comm',
                username   => 'changelog_test_poster',
            }
        ),
        'post_noauth allows a post from an allowed IP, matched via the real request IP'
    );
    DW::Request->reset;
    };

subtest 'LJ::Sysban::block logs the ban and leaves the response to its caller' => sub {
    my @logged;
    no warnings 'redefine';
    local *LJ::statushistory_add = sub { push @logged, [@_]; return 1; };

    # no active request at all (e.g. mailgated.pl -> supportlib -> ...)
    DW::Request->reset;
    ok( eval { LJ::Sysban::block( 0, 'test block, no request', {} ); 1 },
        'block does not die with no active request' )
        or diag("block died: $@");
    is( scalar @logged, 1, 'block logs to statushistory with no active request' );

    # a native Plack-style request, as DW::Controller::Community/Create call it
    my $r = DW::Request::Standard->new( GET 'http://localhost/create' );
    $r->header_in( Host => 'localhost' );
    ok( eval { LJ::Sysban::block( 0, 'test block, with request', {} ); 1 },
        'block does not die with an active native request' )
        or diag("block died: $@");
    is( scalar @logged, 2, 'block logs to statushistory with an active native request' );
    DW::Request->reset;
};

subtest
'LJ::did_post, LJ::check_referer, and LJ::check_form_auth read from DW::Request, not a BML:: fallback'
    => sub {
    DW::Request->reset;
    my $get_r = DW::Request::Standard->new( GET 'http://localhost/foo' );
    $get_r->header_in( Host => 'localhost' );
    is( LJ::did_post(), '', 'GET request is not a post' );

    DW::Request->reset;
    my $post_r = DW::Request::Standard->new( POST 'http://localhost/foo', [] );
    $post_r->header_in( Host => 'localhost' );
    ok( LJ::did_post(), 'POST request is a post' );

    DW::Request->reset;
    ok( !LJ::did_post(), 'no active request is never a post' );

    DW::Request->reset;
    my $referer_r =
        DW::Request::Standard->new( GET 'http://localhost/foo', Referer => 'http://localhost/bar' );
    $referer_r->header_in( Host => 'localhost' );
    ok( LJ::check_referer('/bar'), 'referer picked up from the active native request matches' );
    ok( !LJ::check_referer('/other'),
        'referer picked up from the active request does not match /other' );

    DW::Request->reset;
    ok( LJ::check_referer('/bar'), 'no active request and no explicit referer is treated as OK' );

    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'bmlRuntimeCallersFormAuth';
    my $chal = LJ::form_auth(1);
    DW::Request->reset;
    my $auth_r =
        DW::Request::Standard->new( POST 'http://localhost/foo', [ lj_form_auth => $chal ] );
    $auth_r->header_in( Host           => 'localhost' );
    $auth_r->header_in( 'Content-Type' => 'application/x-www-form-urlencoded' );
    ok( LJ::check_form_auth(),
        'valid form auth token in native post_args validates with no explicit arg' );
    DW::Request->reset;
    };

subtest 'LJ::error_list and LJ::warning_list emit real divs, not the broken <?...?> tags' => sub {
    my $errors = LJ::error_list();
    unlike( $errors, qr/<\?errorbar/, 'error_list no longer emits the broken <?errorbar?> tag' );
    like( $errors, qr/<div class="errorbar">/, 'error_list emits a real errorbar div' );

    my $warnings = LJ::warning_list('a warning');
    unlike( $warnings, qr/<\?warningbar/,
        'warning_list no longer emits the broken <?warningbar?> tag' );
    like( $warnings, qr/<div class="warningbar">/, 'warning_list emits a real warningbar div' );
    like( $warnings, qr/<li>a warning<\/li>/, 'warning_list still lists the given warning text' );
};

subtest 'LJ::error_noremote emits a real login link, not the broken <?needlogin?> tag' => sub {
    DW::Request->reset;
    my $no_req_msg = LJ::error_noremote();
    unlike( $no_req_msg, qr/<\?needlogin\?>/, 'no longer emits the literal <?needlogin?> tag' );
    like( $no_req_msg, qr/log in/i, 'still tells the user to log in' );

    my $r = DW::Request::Standard->new( GET 'http://localhost/poll/?id=5' );
    $r->header_in( Host => 'localhost' );
    my $msg = LJ::error_noremote();
    like(
        $msg,
        qr{href='\Q$LJ::SITEROOT\E/login\?returnto=},
        'includes a login link with a returnto target, built from the active request'
    );
    DW::Request->reset;
};

subtest 'LJ::Poll::render needlogin branch emits a real login link' => sub {
    my $poll_journal = temp_user();
    $poll_journal->update_self( { status => 'A' } );
    my $entry = $poll_journal->t_post_fake_entry();
    my $poll  = LJ::Poll->create(
        entry     => $entry,
        questions => [ { type => 'text', qtext => 'a question' } ],
        name      => 'w5 needlogin test poll',
        isanon    => 'no',
        whovote   => 'all',
        whoview   => 'all',
    );

    LJ::set_remote(undef);
    DW::Request->reset;
    my $r = DW::Request::Standard->new( GET 'http://localhost/entry/view' );
    $r->header_in( Host => 'localhost' );

    my $html = $poll->render( mode => 'enter' );
    unlike( $html, qr/<\?needlogin\?>/,
        'poll voting prompt no longer leaks the literal <?needlogin?> tag' );
    like( $html, qr/log in/i, 'poll voting prompt tells the anonymous viewer to log in' );
    DW::Request->reset;
};

subtest 'LJ::Console::command_reference_html emits a real ml lookup, not the broken <?_ml?> tag' =>
    sub {
    LJ::set_remote(undef);
    my $html = LJ::Console->command_reference_html;
    like( $html, qr/\(unavailable\)/,
        'reference page has at least one unavailable command to exercise' );
    unlike( $html, qr/<\?_ml/, 'no longer emits the literal <?_ml ... _ml?> tag' );
    like(
        $html,
        qr/You are not permitted to run this command\./,
        'emits the real translated not-permitted message'
    );
    };

done_testing;
