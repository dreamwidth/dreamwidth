#!/usr/bin/perl
#
# t/plack-inbox-spam-errors.t
#
# Inbox spam-report mutation and authorization contracts.
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
use Plack::Test;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
use LJ::Message;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $owner   = temp_user();
my $foreign = temp_user();
$_->update_self( { status => 'A' } ) for $owner, $foreign;
my $session = LJ::Session->create( $owner, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'inboxSpamErrors';

sub make_message {
    my ( $from, $to ) = @_;
    my $msg = LJ::Message->new(
        {
            journalid => $from->id,
            otherid   => $to->id,
            msgid     => LJ::alloc_global_counter('M'),
            timesent  => time(),
            subject   => 'spam fixture',
            body      => 'body',
        }
    );
    $msg->save_to_db or die 'Unable to save inbox spam fixture message';
    return $msg;
}

sub markspam_form {
    my ( $content, $url ) = @_;
    return ( grep { defined $_->value('msgid') } HTML::Form->parse( $content, $url ) )[0];
}

test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub {
        my $request = shift;
        $request->header( Cookie => $cookie );
        return $send->($request);
    };

    # Spam reports and bans are moderation actions: record them, never perform them.
    my ( @report_calls, @ban_calls, @ban_log_calls );
    no warnings 'redefine';
    local *LJ::Message::mark_as_spam = sub { push @report_calls, $_[0]->msgid; return 1; };
    local *LJ::set_rel               = sub { push @ban_calls, [@_];            return 1; };
    local *LJ::User::log_event       = sub {
        my ( $u, $evt, $args ) = @_;
        push @ban_log_calls, $args->{actiontarget} if $evt eq 'ban_set';
        return 1;
    };
    my $reports_for = sub {
        my ($msg) = @_;
        return scalar grep { $_ == $msg->msgid } @report_calls;
    };
    my $bans_for = sub {
        my ($target) = @_;
        return scalar grep { $_->[1] == $target->userid && $_->[2] eq 'B' } @ban_calls;
    };

    my $sender = temp_user();
    $sender->update_self( { status => 'A' } );
    my $msg  = make_message( $sender, $owner );
    my $url  = 'http://localhost/inbox/markspam?msgid=' . $msg->msgid;
    my $form = markspam_form( $cb->( GET $url )->content, $url );
    ok( $form, 'confirmation form renders' ) or return;
    $form->value( spam => 1 );
    $form->value( ban  => 1 );
    my $request = $form->click('confirm');
    $request->uri($url);
    my $response = $cb->($request);
    is( $response->code,      303, 'confirmed report redirects to inbox' );
    is( $reports_for->($msg), 1,   'spam is reported exactly once' );
    is( $bans_for->($sender), 1,   'sender is banned exactly once' );
    is( scalar( grep { $_ == $sender->userid } @ban_log_calls ), 1, 'ban is logged once' );
    ok( LJ::Message->load( { msgid => $msg->msgid, journalid => $owner->id } )->valid,
        'reported message remains available' );

    # Only messages received by the remote user can be reported.
    my $token              = $form->value('lj_form_auth');
    my $foreign_sender     = temp_user();
    my $outgoing_recipient = temp_user();
    $_->update_self( { status => 'A' } ) for $foreign_sender, $outgoing_recipient;
    for my $case (
        [ 'foreign',  make_message( $foreign_sender, $foreign ),            $foreign_sender ],
        [ 'outgoing', make_message( $owner,          $outgoing_recipient ), $outgoing_recipient ],
        )
    {
        my ( $name, $other_msg, $other_user ) = @$case;
        $cb->(
            POST '/inbox/markspam',
            Content => [
                confirm      => 1,
                msgid        => $other_msg->msgid,
                spam         => 1,
                ban          => 1,
                lj_form_auth => $token,
            ]
        );
        is( $reports_for->($other_msg), 0, "$name message cannot be reported" );
        is( $bans_for->($other_user),   0, "$name message cannot ban its other party" );
    }
};

done_testing;
