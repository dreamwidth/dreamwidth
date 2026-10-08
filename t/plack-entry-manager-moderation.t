#!/usr/bin/perl
#
# t/plack-entry-manager-moderation.t
#
# Characterize native community-manager entry moderation: delete and
# delete-as-spam of another poster's entry.
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
use LJ::Test qw(temp_user temp_comm);

plan skip_all => 'Manager moderation integration requires a development server'
    unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub fresh_entry {
    my ( $journal, $ditemid ) = @_;
    LJ::Entry::reset_singletons();
    return LJ::Entry->new( $journal, ditemid => $ditemid );
}

sub cookie_for {
    my ($u) = @_;
    my $session = LJ::Session->create( $u, nolog => 1 );
    return
          'ljmastersession='
        . $session->master_cookie_string
        . '; ljloggedin='
        . $session->loggedin_cookie_string;
}

sub maintainer_form {
    my ($content) = @_;
    return ( grep { $_->find_input('action:savemaintainer') }
            HTML::Form->parse( $content, 'http://localhost' ) )[0];
}

my $manager = temp_user();
$manager->update_self( { status => 'A' } );
my $poster = temp_user();
$poster->update_self( { status => 'A' } );
my $outsider = temp_user();
$outsider->update_self( { status => 'A' } );
my $comm = temp_comm();
LJ::set_rel( $comm, $manager, 'A' );

my $manager_cookie  = cookie_for($manager);
my $outsider_cookie = cookie_for($outsider);
my $poster_cookie   = cookie_for($poster);
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'managerModeration';

# A local spamreports write is itself a moderation side effect; stay inert
# across this whole file by recording calls instead of letting any reach the
# database. This local stays in effect until the file ends.
my @spam_calls;
no warnings 'redefine';
local *LJ::mark_entry_as_spam = sub {
    push @spam_calls, [@_];
    return 1;
};
my $spam_dbh = LJ::get_db_writer();
my ($baseline_spam_rows) =
    $spam_dbh->selectrow_array( 'SELECT COUNT(*) FROM spamreports WHERE journalid = ?',
    undef, $comm->userid );

test_psgi $app, sub {
    my $send = shift;

    my $as_manager = sub {
        my ($req) = @_;
        $req->header( Cookie => $manager_cookie );
        return $send->($req);
    };
    my $as_outsider = sub {
        my ($req) = @_;
        $req->header( Cookie => $outsider_cookie );
        return $send->($req);
    };
    my $as_poster = sub {
        my ($req) = @_;
        $req->header( Cookie => $poster_cookie );
        return $send->($req);
    };

    # A valid CSRF token isn't tied to the page that issued it, only the
    # session, so a token lifted from an unrelated page still isolates the
    # authorization guards under test from the CSRF guard.
    my $valid_token_for = sub {
        my ($cb)   = @_;
        my $res    = $cb->( GET '/entry/new' );
        my ($form) = grep { $_->find_input('lj_form_auth') }
            HTML::Form->parse( $res->content, 'http://localhost' );
        return $form ? $form->value('lj_form_auth') : undef;
    };

    subtest 'manager deletes another poster entry through the maintainer form' => sub {
        my $entry = $poster->t_post_fake_comm_entry(
            $comm,
            subject => 'Manager delete target subject',
            body    => 'Manager delete target body',
        );
        my $url = '/entry/' . $comm->user . '/' . $entry->ditemid . '/edit';
        my $get = $as_manager->( GET $url );
        is( $get->code, 200, 'manager GET renders the maintainer form' );
        my $form = maintainer_form( $get->content );
        ok( $form, 'maintainer form parses' ) or BAIL_OUT('maintainer form missing');

        # A filled-in override field must not divert a delete click into the
        # property-save path.
        $form->value( 'prop_opt_nocomments_maintainer', 1 );
        $form->action( 'http://localhost' . $url );
        my $res = $as_manager->( $form->click('action:delete') );
        ok( !$res->header('Location'),
            'manager delete response is not the savemaintainer redirect' );
        my $deleted = fresh_entry( $comm, $entry->ditemid );
        ok( !$deleted->valid, 'forced-fresh read proves the entry is actually deleted' );
    };

    subtest 'manager deletes another poster entry as spam' => sub {
        my $entry = $poster->t_post_fake_comm_entry(
            $comm,
            subject => 'Manager spam target subject',
            body    => 'Manager spam target body',
        );
        my $url  = '/entry/' . $comm->user . '/' . $entry->ditemid . '/edit';
        my $get  = $as_manager->( GET $url );
        my $form = maintainer_form( $get->content );
        ok( $form, 'maintainer form parses for spam-delete case' )
            or BAIL_OUT('maintainer form missing');
        $form->action( 'http://localhost' . $url );
        $as_manager->( $form->click('action:deletespam') );
        my $deleted = fresh_entry( $comm, $entry->ditemid );
        ok( !$deleted->valid,
            'forced-fresh read proves the entry is deleted after delete-as-spam' );

        is( scalar @spam_calls, 1, 'delete-as-spam calls LJ::mark_entry_as_spam exactly once' );
        my ( $called_journal, $called_jitemid ) = @{ $spam_calls[0] };
        ok( LJ::isu($called_journal) && $called_journal->equals($comm),
            'the spam call is for the expected journal' );
        is( $called_jitemid, $entry->jitemid, 'the spam call is for the expected entry' );
    };

    subtest 'a non-manager cannot delete another poster entry' => sub {
        my $entry = $poster->t_post_fake_comm_entry(
            $comm,
            subject => 'Non-manager target subject',
            body    => 'Non-manager target body',
        );
        my $url = '/entry/' . $comm->user . '/' . $entry->ditemid . '/edit';

        # A valid token isolates the authorization guard from the CSRF guard.
        my $token = $valid_token_for->($as_outsider);
        ok( $token, 'outsider has a real CSRF token to attempt with' );
        my $before_calls = scalar @spam_calls;
        $as_outsider->( POST $url, Content => [ 'action:delete' => 1, lj_form_auth => $token ] );
        my $after = fresh_entry( $comm, $entry->ditemid );
        ok( $after->valid, 'outsider with a VALID token still cannot delete another poster entry' );
        is(
            $after->event_raw,
            'Non-manager target body',
            'outsider leaves the entry body unchanged'
        );
        is( scalar @spam_calls,
            $before_calls, 'outsider with a valid token calls LJ::mark_entry_as_spam zero times' );
    };

    subtest
        'a non-manager poster sending delete-as-spam on their own entry records no spam report' =>
        sub {
        my $own_entry = $poster->t_post_fake_comm_entry(
            $comm,
            subject => 'Poster own deletespam subject',
            body    => 'Poster own deletespam body',
        );
        my $url   = '/entry/' . $comm->user . '/' . $own_entry->ditemid . '/edit';
        my $token = $valid_token_for->($as_poster);
        ok( $token, 'poster has a real CSRF token' );

        my $spam_calls_before = scalar @spam_calls;
        $as_poster->( POST $url, Content => [ 'action:deletespam' => 1, lj_form_auth => $token ] );
        is( scalar @spam_calls,
            $spam_calls_before,
            'a poster sending deletespam on their own entry never calls LJ::mark_entry_as_spam' );
        };

    subtest 'CSRF denial for manager delete' => sub {
        my $entry = $poster->t_post_fake_comm_entry(
            $comm,
            subject => 'CSRF target subject',
            body    => 'CSRF target body',
        );
        my $url  = '/entry/' . $comm->user . '/' . $entry->ditemid . '/edit';
        my $get  = $as_manager->( GET $url );
        my $form = maintainer_form( $get->content );
        ok( $form, 'maintainer form parses for CSRF case' ) or BAIL_OUT('maintainer form missing');
        $form->value( 'lj_form_auth', 'deliberately-invalid-token' );
        $form->action( 'http://localhost' . $url );
        my $before_invalid = scalar @spam_calls;
        my $res            = $as_manager->( $form->click('action:delete') );
        unlike( $res->content, qr/deleted|entry.*removed/i,
            'an invalid form-auth token does not perform a delete' );
        ok(
            fresh_entry( $comm, $entry->ditemid )->valid,
            'an invalid form-auth token leaves the entry intact'
        );
        is( scalar @spam_calls,
            $before_invalid, 'an invalid form-auth token calls LJ::mark_entry_as_spam zero times' );
    };
};

my ($final_spam_rows) =
    $spam_dbh->selectrow_array( 'SELECT COUNT(*) FROM spamreports WHERE journalid = ?',
    undef, $comm->userid );
is( $final_spam_rows, $baseline_spam_rows,
    'no spamreports row was ever actually written, across the whole file' );

done_testing;
