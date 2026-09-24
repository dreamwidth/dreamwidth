#!/usr/bin/perl
# Characterize ordinary own-entry deletion through the native edit form.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use HTML::Form;
use Plack::Test;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Entry;
use LJ::Session;
use LJ::Test qw(temp_user);

plan skip_all => 'Entry deletion integration requires a development server'
    unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub edit_form {
    my ($content) = @_;
    return (
        grep {
                   ( $_->attr('id') || '' ) eq 'js-post-entry'
                && $_->find_input('subject')
                && $_->find_input('event')
        } HTML::Form->parse( $content, 'http://localhost' )
    )[0];
}

sub fresh_entry {
    my ( $owner, $ditemid ) = @_;
    LJ::Entry::reset_singletons();
    return LJ::Entry->new( $owner, ditemid => $ditemid );
}

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $target = $owner->t_post_fake_entry(
    subject  => 'Delete target private subject',
    body     => 'Delete target private body',
    security => 'private',
);
my $unrelated = $owner->t_post_fake_entry(
    subject  => 'Unrelated private subject',
    body     => 'Unrelated private body',
    security => 'private',
);
my $session = LJ::Session->create( $owner, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryDeleteParity';

my $edit_path = '/entry/' . $owner->user . '/' . $target->ditemid . '/edit';

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    my $res = $request->( GET $edit_path );
    is( $res->code, 200, 'authenticated owner receives the native edit form' );
    my $form = edit_form( $res->content );
    ok( $form, 'actual native edit form parses' ) or BAIL_OUT('edit form missing');
    ok( $form->find_input('lj_form_auth'),  'rendered delete form carries a CSRF token' );
    ok( $form->find_input('action:delete'), 'rendered edit form carries the actual delete action' );
    like(
        $res->content,
        qr/(?:delete_confirm|entryform\.delete\.confirm)/,
        'edit form renders delete-confirmation client contract'
    );
    is(
        $form->value('subject'),
        'Delete target private subject',
        'confirmation GET renders target subject without deleting it'
    );
    is(
        $form->value('event'),
        'Delete target private body',
        'confirmation GET renders target body without deleting it'
    );
    ok(
        fresh_entry( $owner, $target->ditemid )->valid,
        'confirmation GET leaves target entry intact'
    );
    ok(
        fresh_entry( $owner, $unrelated->ditemid )->valid,
        'confirmation GET leaves unrelated entry intact'
    );

    $form->action( 'http://localhost' . $edit_path );
    $res = $request->( $form->click('action:delete') );
    is( $res->code, 200, 'actual confirmation delete POST returns the handler response' );
    like(
        $res->content,
        qr/(?:deleted|delete succeeded|entry.*removed)/i,
        'delete POST has a meaningful user-facing result'
    );

    my $deleted = fresh_entry( $owner, $target->ditemid );
    ok( !$deleted->valid,
        'forced-fresh target entry is deleted after the actual confirmation POST' );
    my $still_there = fresh_entry( $owner, $unrelated->ditemid );
    ok( $still_there->valid, 'forced-fresh unrelated entry remains after target delete' );
    is( $still_there->security, 'private', 'unrelated entry retains private security' );
    is(
        $still_there->subject_raw,
        'Unrelated private subject',
        'unrelated entry retains exact subject'
    );
    is( $still_there->event_raw, 'Unrelated private body', 'unrelated entry retains exact body' );
};

done_testing;
