#!/usr/bin/perl
#
# t/plack-entry-maintainer.t
#
# Characterize the read-only entry picker and the community-manager
# "maintainer" admin-override editing of another poster's entry.
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
plan skip_all => 'Picker integration requires a development server' unless $LJ::IS_DEV_SERVER;
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $owner    = temp_user();
my $outsider = temp_user();
$owner->update_self(    { status => 'A' } );
$outsider->update_self( { status => 'A' } );
my $session = LJ::Session->create( $owner, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryPickerBaseline';

my @spam_checks;
local $LJ::HOOKS{spam_check} = [ sub { push @spam_checks, [@_]; return; } ];

# The picker's per-entry forms are the ones whose submit button is itemid-<ditemid>.
sub entry_forms {
    my ( $content, $base ) = @_;
    return grep {
        grep { ( $_->id // '' ) =~ /^itemid-\d+$/ }
            $_->inputs
    } HTML::Form->parse( $content, $base );
}

test_psgi $app, sub {
    my $send = shift;
    $owner->t_post_fake_entry(
        subject  => 'Picker private subject',
        body     => 'Picker private body',
        security => 'private',
    );
    my $res = $send->( GET '/editjournal?usejournal=' . $owner->user );
    is( scalar entry_forms( $res->content, 'http://localhost/editjournal' ),
        0, 'logged-out visitor sees no entry forms' );
    unlike( $res->content, qr/Picker private/, 'logged-out visitor sees no entry summaries' );
};

test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };
    my $comm = temp_comm();
    LJ::set_rel( $comm, $owner, 'A' );
    my $own_entry = $owner->t_post_fake_comm_entry( $comm, body => 'Manager community body' );
    my $other_entry =
        $outsider->t_post_fake_comm_entry( $comm, body => 'Other poster community body' );

    # A POST to /editjournal with an itemid is a stale old-editor submission,
    # so each entry's Edit button must GET that entry's native edit URL.
    my $picker = $cb->( GET '/editjournal?usejournal=' . $comm->user );
    my @forms  = entry_forms( $picker->content, 'http://localhost/editjournal' );
    my %seen;
    for my $form (@forms) {
        is( $form->method, 'GET', 'picker entry form submits by GET' );
        if ( $form->action->path =~ m{^/entry/\Q@{[ $comm->user ]}\E/(\d+)/edit$} ) {
            $seen{$1} = 1;
        }
        else {
            fail( 'picker entry form targets the community entry edit URL: ' . $form->action );
        }
    }
    is_deeply(
        [ sort { $a <=> $b } keys %seen ],
        [ sort { $a <=> $b } $own_entry->ditemid, $other_entry->ditemid ],
        'community picker lists both posters\' entries with native edit actions'
    );

    LJ::set_logprop( $comm, $other_entry->jitemid, { opt_preformatted => 1 } );
    LJ::Entry::reset_singletons();
    my $seeded           = LJ::Entry->new( $comm, ditemid => $other_entry->ditemid );
    my $original_body    = $seeded->event_raw;
    my $original_subject = $seeded->subject_raw;

    my $native_url = '/entry/' . $comm->user . '/' . $other_entry->ditemid . '/edit';
    my $native_get = $cb->( GET $native_url );
    is( $native_get->code, 200, 'authorized manager receives native maintainer form' );
    my ($native_form) = grep { $_->find_input('action:savemaintainer') }
        HTML::Form->parse( $native_get->content, 'http://localhost' . $native_url );
    ok( $native_form, 'native rendered maintainer save form exists' )
        or BAIL_OUT('maintainer form missing');
    $native_form->value( 'prop_adult_content_maintainer_reason', 'native reason marker' );
    $native_form->value( 'prop_adult_content_maintainer',        'concepts' );
    $native_form->value( 'prop_opt_nocomments_maintainer',       1 );
    $native_form->action( 'http://localhost' . $native_url );
    my $native_save = $cb->( $native_form->click('action:savemaintainer') );
    is( $native_save->code, 302, 'native property-only save redirects after success' );
    LJ::Entry::reset_singletons();
    my $saved = LJ::Entry->new( $comm, ditemid => $other_entry->ditemid );
    is(
        $saved->prop('adult_content_maintainer_reason'),
        'native reason marker',
        'save persists reason'
    );
    is( $saved->prop('adult_content_maintainer'), 'concepts', 'save persists level' );
    is( $saved->prop('opt_nocomments_maintainer') || 0, 1, 'save persists comments override' );
    is( $saved->event_raw,   $original_body,    'save preserves the poster\'s body' );
    is( $saved->subject_raw, $original_subject, 'save preserves the poster\'s subject' );
    is( $saved->prop('opt_preformatted') || '', 1, 'save preserves an unrelated property' );
};

subtest 'maintainer comments-disable box defaults unticked and saves unticked' => sub {

    # The override checkbox must not render pre-checked when
    # opt_nocomments_maintainer is unset (checked="0" is ticked in a browser),
    # and an unticked save must not disable comments.
    my $comm = temp_comm();
    LJ::set_rel( $comm, $owner, 'A' );
    my $entry = $outsider->t_post_fake_comm_entry( $comm, body => 'Regression body' );
    LJ::set_logprop( $comm, $entry->jitemid, { opt_nocomments_maintainer => 0 } );
    LJ::Entry::reset_singletons();

    my $url = '/entry/' . $comm->user . '/' . $entry->ditemid . '/edit';
    test_psgi $app, sub {
        my $send = shift;
        my $cb  = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req); };
        my $get = $cb->( GET $url );
        is( $get->code, 200, 'maintainer form renders' );
        unlike(
            $get->content,
            qr/<input(?=[^>]*name="prop_opt_nocomments_maintainer")[^>]*\bchecked=/,
            'comments-disable box is not pre-ticked when the maintainer prop is unset'
        );
        my ($form) = grep { $_->find_input('action:savemaintainer') }
            HTML::Form->parse( $get->content, 'http://localhost' . $url );
        ok( $form, 'maintainer save form parses' );
        $form->action( 'http://localhost' . $url );
        my $save = $cb->( $form->click('action:savemaintainer') );
        is( $save->code, 302, 'save without ticking redirects on success' );
        LJ::Entry::reset_singletons();
        is(
            LJ::Entry->new( $comm, ditemid => $entry->ditemid )->prop('opt_nocomments_maintainer')
                || 0,
            0,
            'saving with the box unticked leaves comments enabled'
        );
    };
};

done_testing;
