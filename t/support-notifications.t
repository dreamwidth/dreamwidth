# t/support-notifications.t
#
# Tests for support notification preferences and delivery.
#
# Authors:
#     Dreamwidth contributors
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
use DW::IncomingEmail;
use LJ::Support;
use LJ::Test qw(temp_user with_fake_memcache);

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

local $LJ::IS_DEV_SERVER              = 1;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'supportNotifyTest';
local $LJ::EMAIL_REPLY_DOMAIN         = 'reply.example.invalid';

my $catkey   = 'tn_' . lc LJ::rand_chars(12);
my $mailbox  = "$catkey\@example.invalid";
my $category = LJ::Support::define_cat(
    {
        catkey         => $catkey,
        catname        => 'Notification test',
        public_read    => '0',
        public_help    => '0',
        allow_screened => 1,
        no_autoreply   => 1,
        replyaddress   => $mailbox,
    }
) or die 'Could not create support category';

my $dbh = LJ::get_db_writer();
my $spid;

END {
    if ($spid) {
        for my $table (qw(supportlog support_youreplied supportprop support)) {
            $dbh->do( "DELETE FROM $table WHERE spid=?", undef, $spid );
        }
    }
    if ($category) {
        $dbh->do( 'DELETE FROM supportnotify WHERE spcatid=?', undef, $category );
        LJ::Support::delete_cat($category);
    }
}

my ( @jobs, @mail );
{
    no warnings 'redefine';
    *DW::TaskQueue::dispatch = sub {
        my ( $class, $task ) = @_;
        push @jobs, $task if $task->isa('DW::Task::SupportNotify');
        return 1;
    };
    *LJ::send_mail = sub {
        push @mail, $_[0] if $_[0]{bcc};
        return 1;
    };
}

sub expect_delivery {
    my ( $description, @expected ) = @_;
    @mail = ();
    $_->work(undef) for splice @jobs;
    my @recipients = sort map { split /, /, $_->{bcc} } @mail;
    is_deeply( \@recipients, [ sort map { $_->email_raw } @expected ], $description );
}

with_fake_memcache {
    my ( $requester, $helper, $new, $regreen, $all, $all_reader, $off, $no_access ) =
        map { temp_user() } 1 .. 8;
    for my $user ( $requester, $helper, $new, $regreen, $all, $all_reader, $off, $no_access ) {
        $user->update_self( { status => 'A', email => $user->user . '@example.invalid' } );
        next if $user->id == $no_access->id;
        $user->grant_priv( 'supportread', $catkey ) or die 'Could not grant supportread';
    }
    $_->grant_priv( 'supporthelp', $catkey )
        or die 'Could not grant supporthelp'
        for ( $helper, $all );

    test_psgi $app, sub {
        my $client = shift;
        my $post   = sub {
            my ( $user, $action, %fields ) = @_;
            LJ::set_remote($user);
            delete $LJ::REQ_GLOBAL{form_auth_chal};
            my $form_auth = LJ::form_auth(1);
            LJ::set_remote(undef);
            my $as = $user->user;
            return $client->(
                POST "http://localhost/support/$action?as=$as",
                Content => [ lj_form_auth => $form_auth, %fields ],
            );
        };

        for my $preference (
            [ $new,        'new' ],
            [ $regreen,    'new_and_regreen' ],
            [ $all,        'all' ],
            [ $all_reader, 'all' ],
            [ $off,        'all' ],
            [ $off,        'off' ],
            [ $no_access,  'new_and_regreen' ],
            [ $requester,  'new_and_regreen' ],
            )
        {
            my ( $user, $level ) = @$preference;
            my $response = $post->( $user, 'changenotify', "spcatid_$category" => $level );
            is( $response->code, 200, "$level submission succeeds" );
        }

        my $saved = sub {
            return $dbh->selectrow_array(
                'SELECT level FROM supportnotify WHERE spcatid=? AND userid=?',
                undef, $category, $_[0]->id );
        };
        is( scalar $saved->($regreen), 'new_and_regreen', 'New and Regreens persists' );
        is( scalar $saved->($no_access), undef, 'Unreadable category cannot be subscribed to' );
        is( scalar $saved->($off),       undef, 'Off stores no subscription' );

        my @errors;
        $spid = LJ::Support::file_request(
            \@errors,
            {
                spcatid          => $category,
                reqtype          => 'user',
                requserid        => $requester->id,
                reqemail         => $requester->email_raw,
                reqname          => 'Test requester',
                subject          => 'Test request',
                body             => 'Initial request',
                language         => $LJ::DEFAULT_LANG,
                ignore_dup_check => 1,
            }
        ) or BAIL_OUT( 'Could not file support request: ' . join ', ', @errors );
        expect_delivery( 'New requests reach all three subscribed levels',
            $new, $regreen, $all, $all_reader, $requester );

        my $reply = sub {
            my ( $who, %fields ) = @_;
            my $response = $post->(
                $who, 'append_request',
                spid         => $spid,
                summary      => '',
                reply        => '',
                internal     => '',
                internaltype => '',
                %fields
            );
            is( $response->code, 200, 'Reply submission succeeds' );
        };

        $reply->( $helper, replytype => 'answer', reply => 'Please try again.' );
        expect_delivery( 'An answer reaches both All subscribers', $all, $all_reader );
        $dbh->do(
            'UPDATE support SET timetouched=UNIX_TIMESTAMP()-20, '
                . 'timelasthelp=UNIX_TIMESTAMP()-10 WHERE spid=?',
            undef, $spid
        );
        $reply->( $requester, replytype => 'comment', reply => 'I tried again.' );
        my $after_reply = LJ::Support::load_request($spid);
        is(
            LJ::Support::open_request_status( @{$after_reply}{qw(timetouched timelasthelp)} ),
            'still needs help',
            'Requester follow-up returns an answered request to the queue'
        );
        expect_delivery(
            'A requester follow-up reaches New and Regreens and All, except the author',
            $regreen, $all, $all_reader );

        $reply->( $helper, replytype => 'comment', reply => 'A staff comment.' );
        expect_delivery( 'A staff comment reaches All only', $all, $all_reader );
        $reply->( $helper, replytype => 'screened', reply => 'A screened answer.' );
        expect_delivery( 'A screened answer reaches only All with permission', $all );
        $reply->( $helper, internaltype => 'internal', internal => 'An internal comment.' );
        expect_delivery( 'An internal comment reaches only All with permission', $all );
        $reply->( $helper, internaltype => 'internal', touch => 1 );
        expect_delivery( 'A staff touch logged as an internal comment is not a regreen', $all );
        ok( LJ::Support::touch_request($spid), 'Standalone touch works' );
        expect_delivery('A standalone touch sends no mail');

        $dbh->do( q{UPDATE support SET state='closed' WHERE spid=?}, undef, $spid );
        my $sp = LJ::Support::load_request($spid);
        my ( $localpart, $domain ) = split /\@/, $mailbox;
        my $auth = LJ::Support::mini_auth($sp);
        my $to   = "$localpart+$spid" . "z$auth\@$domain";
        my $from = $requester->email_raw;
        ok( DW::IncomingEmail->process(<<"EMAIL"), 'Incoming support reply is processed' );
From: $from
To: $to
Subject: Re: Test request
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

The problem came back.
EMAIL
        is( LJ::Support::load_request($spid)->{state}, 'open', 'Email reply reopens the request' );
        expect_delivery( 'An email follow-up also reaches New and Regreens and All',
            $regreen, $all, $all_reader, $requester );
    };
};

done_testing;
