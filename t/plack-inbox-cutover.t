#!/usr/bin/perl
#
# t/plack-inbox-cutover.t
#
# Native inbox routes: retained /inbox/new* links redirect with their query
# args, and POSTs to those links are handled rather than dropped.
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

use HTML::Form;
use HTTP::Request::Common;
use Plack::Test;
use Test::More;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Event::AddedToCircle;
use LJ::Message;
use LJ::Session;
use LJ::Test qw(temp_user);

plan skip_all => 'Inbox cutover characterization requires a development server'
    unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub form_token {
    my ($content) = @_;
    return $1 if $content =~ /name=['"]lj_form_auth['"][^>]*value=['"]([^'"]+)/;
    return;
}

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'inboxCutover';

my $u  = temp_user();
my $u2 = temp_user();
$_->update_self( { status => 'A' } ) for $u, $u2;
my $session = LJ::Session->create( $u, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;

# The inbox caches item state on the user object; reload to see server writes.
sub fresh_inbox { LJ::load_userid( $u->id, 1 )->notification_inbox }
sub item_read { LJ::NotificationItem->new( LJ::load_userid( $u->id, 1 ), $_[0] )->read }

sub new_item {
    return $u->notification_inbox->enqueue( event => LJ::Event::AddedToCircle->new( $u2, $u, 2 ) )
        ->qid;
}
my $seed_qid = new_item();

test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };

    my $msg = LJ::Message->new(
        {
            journalid => $u2->id,
            otherid   => $u->id,
            msgid     => LJ::alloc_global_counter('M'),
            timesent  => time(),
            subject   => 'cutover fixture',
            body      => 'body',
        }
    );
    $msg->save_to_db or die 'unable to save cutover markspam fixture message';

    # Notification emails already sent link to /inbox/new*.
    for my $case (
        [ '/inbox/new?view=circle',                   '/inbox?view=circle' ],
        [ '/inbox/new/compose?user=' . $u2->user,     '/inbox/compose?user=' . $u2->user ],
        [ '/inbox/new/markspam?msgid=' . $msg->msgid, '/inbox/markspam?msgid=' . $msg->msgid ],
        )
    {
        my ( $old, $new ) = @$case;
        my $res = $cb->( GET $old );
        like( $res->header('Location') || '', qr{\Q$new\E$}, "$old redirects to $new" );
    }

    my $index_token = form_token( $cb->( GET '/inbox' )->content );
    ok( $index_token, 'inbox supplies a CSRF token' );

    my $before = fresh_inbox()->is_bookmark($seed_qid);
    $cb->( GET "/inbox/?bookmark_off=$seed_qid" );
    is( fresh_inbox()->is_bookmark($seed_qid),
        $before, 'bookmark toggle without a token does not change bookmark state' );
    my $toggle =
        $cb->( GET "/inbox/?bookmark_off=$seed_qid&lj_form_auth=" . LJ::eurl($index_token) );
    is( fresh_inbox()->is_bookmark($seed_qid), 1, 'bookmark toggle with a valid token applies' );
    unlike( $toggle->header('Location') || '',
        qr/lj_form_auth=/,
        'the redirect after a bookmark toggle drops the token from the address bar' );

    my $form_qid = new_item();
    my ($actions_form) =
        grep { $_->find_input('mark_read') }
        HTML::Form->parse( $cb->( GET '/inbox' )->content, 'http://localhost/inbox' );
    ok( $actions_form && $actions_form->find_input("check_$form_qid"),
        'the rendered actions form lists the item' )
        or return;
    $actions_form->value( "check_$form_qid" => $form_qid );
    $cb->( $actions_form->click('mark_read') );
    ok( item_read($form_qid), 'submitting the rendered actions form marks the item read' );

    # Tabs left open on /inbox/new* must not lose their POST to a redirect.
    for my $path ( '/inbox/new', '/inbox/new/' ) {
        my $qid = new_item();
        my $res = $cb->(
            POST $path,
            Content => [ mark_read => 1, "check_$qid" => $qid, lj_form_auth => $index_token ],
        );
        ok( !$res->header('Location'), "POST to $path is not redirected" );
        ok( item_read($qid),           "POST to $path marks the item read" );
    }

    my $compose_token = form_token( $cb->( GET '/inbox/compose' )->content );
    my $compose       = $cb->(
        POST '/inbox/new/compose',
        Content => [
            mode         => 'send',
            msg_to       => $u2->user,
            msg_subject  => 'stale tab subject',
            msg_body     => 'stale tab body',
            lj_form_auth => $compose_token,
        ],
    );
    like( $compose->header('Location') || '',
        qr{/inbox$}, 'POST to /inbox/new/compose sends and lands on the success redirect' );
};

done_testing;
