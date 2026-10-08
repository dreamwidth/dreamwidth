#!/usr/bin/perl
#
# t/plack-entry-edit-parity.t
#
# Characterize ordinary owned-entry edit form persistence.
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

use LJ::Entry;
use LJ::Session;
use LJ::Test qw(temp_user);

plan skip_all => 'Entry integration requires a development server' unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub edit_form {
    my ($content) = @_;
    return ( grep { $_->find_input('subject') && $_->find_input('event') }
            HTML::Form->parse( $content, 'http://localhost' ) )[0];
}

sub fresh_entry {
    my ( $owner, $ditemid ) = @_;
    LJ::Entry::reset_singletons();
    return LJ::Entry->new( $owner, ditemid => $ditemid );
}

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $entry = $owner->t_post_fake_entry(
    subject => 'Editor parity original subject',
    body    => 'Editor parity original body',
);
my $ditemid = $entry->ditemid;

my $session = LJ::Session->create( $owner, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryEditParity';

my @spam_checks;
local $LJ::HOOKS{spam_check} = [ sub { push @spam_checks, [@_]; return; } ];

my $path = '/entry/' . $owner->user . '/' . $ditemid . '/edit';

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    my $form = edit_form( $request->( GET $path )->content );
    ok( $form, 'actual owned-entry edit form is rendered' ) or BAIL_OUT('edit form missing');
    $form->action( 'http://localhost' . $path );
    $form->value( subject          => 'Editor parity changed subject' );
    $form->value( event            => 'Editor parity changed body' );
    $form->value( taglist          => 'editor-one, editor-two' );
    $form->value( current_location => 'Editor parity location' );
    $request->( $form->click('action:post') );

    my $fresh = fresh_entry( $owner, $ditemid );
    is( $fresh->event_raw, 'Editor parity changed body', 'edit persists the changed body' );
    is_deeply( [ sort $fresh->tags ], [ 'editor-one', 'editor-two' ], 'edit persists tags' );
    is( $fresh->prop('current_location'), 'Editor parity location', 'edit persists location' );

    # Blank fields must clear stored metadata, not be skipped as absent.
    $form = edit_form( $request->( GET $path )->content );
    $form->action( 'http://localhost' . $path );
    $form->value( taglist          => '' );
    $form->value( current_location => '' );
    $request->( $form->click('action:post') );

    $fresh = fresh_entry( $owner, $ditemid );
    is_deeply( [ $fresh->tags ], [], 'blank taglist clears prior tags' );
    is( $fresh->prop('current_location'), undef, 'blank location clears prior location' );
    is(
        $fresh->subject_raw,
        'Editor parity changed subject',
        'metadata clearing preserves subject'
    );
    is( $fresh->event_raw, 'Editor parity changed body', 'metadata clearing preserves body' );

    my $timestamp_before = $fresh->eventtime_mysql;
    $form = edit_form( $request->( GET $path )->content );
    $form->action( 'http://localhost' . $path );
    $form->value( event          => 'Body that must not be saved' );
    $form->value( entrytime_date => 'not-a-date' );
    $form->value( entrytime_time => 'not-a-time' );
    my $res = $request->( $form->click('action:post') );
    is( $res->code, 200, 'invalid timestamp re-renders the form' );
    like( $res->content, qr/not-a-date/, 'invalid date is retained' );
    like( $res->content, qr/Body that must not be saved/, 'submitted body is retained' );
    $fresh = fresh_entry( $owner, $ditemid );
    is( $fresh->eventtime_mysql, $timestamp_before, 'invalid timestamp leaves the time unchanged' );
    is( $fresh->event_raw, 'Editor parity changed body', 'invalid timestamp saves nothing' );
};

done_testing;
