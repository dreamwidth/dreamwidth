#!/usr/bin/perl
#
# t/plack-inbox-compose-errors.t
#
# Authenticated compose rejection regressions; delivery is always replaced locally.
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
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $sender    = temp_user();
my $recipient = temp_user();
$sender->update_self(    { status => 'A' } );
$recipient->update_self( { status => 'A' } );
my $session = LJ::Session->create( $sender, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;

sub form_token {
    my ($content) = @_;
    return $1 if $content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
    return;
}

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'inboxComposeErrors';
test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };
    my $get  = $cb->( GET '/inbox/compose' );
    is( $get->code, 200, 'authenticated compose form renders' );
    my $token = form_token( $get->content );
    ok( $token, 'rendered compose form supplies CSRF token' );
    my @base = (
        mode        => 'send',
        msg_to      => $recipient->user,
        msg_subject => 'Subject retained marker',
        msg_body    => 'Body retained marker',
    );

    $recipient->set_prop( 'opt_usermsg', 'N' );
    my $res = $cb->( POST '/inbox/compose', Content => [ @base, lj_form_auth => $token ] );
    is( $res->code, 200, 'recipient denial rerenders compose instead of failing' );
    like( $res->content, qr/Subject retained marker/, 'recipient denial retains subject' );
    like( $res->content, qr/Body retained marker/,    'recipient denial retains body' );
    like(
        $res->content,
        qr/chosen not to receive messages/i,
        'recipient denial renders useful error'
    );
    ok( !$res->header('Location'), 'recipient denial has no success redirect' );

    $recipient->set_prop( 'opt_usermsg', 'Y' );
    {
        no warnings 'redefine';
        local *LJ::Message::can_send =
            sub { push @{ $_[1] }, 'Forced can_send failure'; return 0; };
        local *LJ::Message::send = sub { die 'send must not run after can_send failure' };
        $res = $cb->( POST '/inbox/compose', Content => [ @base, lj_form_auth => $token ] );
        is( $res->code, 200, 'can_send failure rerenders compose' );
        like(
            $res->content,
            qr/Forced can_send failure/,
            'can_send errors retain their actual sentence'
        );
        unlike(
            $res->content,
            qr/missing string/i,
            'can_send sentence is not treated as an ML key'
        );
        like( $res->content, qr/Subject retained marker/, 'can_send failure retains subject' );
        like( $res->content, qr/Body retained marker/,    'can_send failure retains body' );
        ok( !$res->header('Location'), 'can_send failure has no success redirect' );
    }
    for my $bad ( undef, 'invalid' ) {
        my @payload = @base;
        push @payload, lj_form_auth => $bad if defined $bad;
        my $called = 0;
        no warnings 'redefine';
        local *LJ::Message::send = sub { $called++; die 'delivery must not run for bad CSRF' };
        $res = $cb->( POST '/inbox/compose', Content => \@payload );
        unlike( $res->content, qr/Message Sent/i, 'bad CSRF does not report success' );
        is( $called, 0, 'bad CSRF has no delivery effect' );
    }
};

# Legacy (htdocs/inbox/compose.bml) required a validated sender; the native
# port only checked the user_messaging feature flag.
test_psgi $app, sub {
    my $send        = shift;
    my $unvalidated = temp_user();
    $unvalidated->update_self( { status => 'N' } );
    my $u_session = LJ::Session->create( $unvalidated, nolog => 1 );
    my $u_cookie =
          'ljmastersession='
        . $u_session->master_cookie_string
        . '; ljloggedin='
        . $u_session->loggedin_cookie_string;
    my $u_cb = sub { my $req = shift; $req->header( Cookie => $u_cookie ); return $send->($req); };

    my $get = $u_cb->( GET '/inbox/compose' );
    is( $get->code, 303, 'unvalidated sender is redirected away from compose' );
    like( $get->header('Location') || '',
        qr{/inbox$}, 'unvalidated sender is redirected to the inbox' );

    # index_handler has no validation gate, so it is a valid source for a
    # real CSRF token tied to this same unvalidated session.
    my $index_get = $u_cb->( GET '/inbox' );
    my $u_token   = form_token( $index_get->content );
    ok( $u_token, 'unvalidated sender can still obtain a real CSRF token elsewhere' );

    my $called = 0;
    no warnings 'redefine';
    local *LJ::Message::send =
        sub { $called++; die 'delivery must not run for an unvalidated sender' };
    my $post = $u_cb->(
        POST '/inbox/compose',
        Content => [
            mode         => 'send',
            msg_to       => $recipient->user,
            msg_subject  => 'Should never send',
            msg_body     => 'Should never send',
            lj_form_auth => $u_token,
        ]
    );
    is( $post->code, 303, 'unvalidated sender POST is also redirected before composing' );
    is( $called,     0,   'unvalidated sender has no delivery effect' );
};

# The user_messaging feature flag is a separate gate from sender validation,
# and now uses its own (previously orphaned) .messaging.disabled string.
test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };

    my $orig_enabled = \&LJ::is_enabled;
    no warnings 'redefine';
    local *LJ::is_enabled = sub {
        return 0 if $_[0] eq 'user_messaging';
        return $orig_enabled->(@_);
    };

    my $get = $cb->( GET '/inbox/compose' );
    is( $get->code, 303, 'disabled messaging redirects away from compose' );
    like( $get->header('Location') || '', qr{/inbox$},
        'disabled messaging redirects to the inbox' );

    # index_handler has no messaging-flag gate, so it is a valid source for a
    # real CSRF token tied to this same session while messaging is disabled.
    my $index_get      = $cb->( GET '/inbox' );
    my $disabled_token = form_token( $index_get->content );
    ok( $disabled_token,
        'a real CSRF token is still available elsewhere while messaging is disabled' );

    my $called = 0;
    local *LJ::Message::send =
        sub { $called++; die 'delivery must not run while messaging is disabled' };
    my $post = $cb->(
        POST '/inbox/compose',
        Content => [
            mode         => 'send',
            msg_to       => $recipient->user,
            msg_subject  => 'Should never send',
            msg_body     => 'Should never send',
            lj_form_auth => $disabled_token,
        ]
    );
    is( $post->code, 303, 'disabled messaging POST is also redirected before composing' );
    is( $called,     0,   'disabled messaging has no delivery effect' );
};

done_testing;
