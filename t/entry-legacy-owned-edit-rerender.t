#!/usr/bin/perl
# Characterize callable legacy owned-edit rerendering without registering old routes.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use HTML::Form;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request::Standard;
use DW::Controller::Entry;
use DW::Entry::Legacy;
use DW::FormErrors;
use LJ::Entry;
use LJ::Test qw(temp_user);

sub fresh_entry {
    my ( $owner, $ditemid ) = @_;
    LJ::Entry::reset_singletons();
    return LJ::Entry->new( $owner, ditemid => $ditemid );
}

sub edit_form {
    my ($content) = @_;
    return ( grep { $_->find_input('subject') && $_->find_input('event') }
            HTML::Form->parse( $content, 'http://localhost' ) )[0];
}

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $entry = $owner->t_post_fake_entry(
    subject => 'Owned rerender original subject',
    body    => 'Owned rerender original body',
);
my $unrelated = $owner->t_post_fake_entry(
    subject => 'Unrelated rerender subject',
    body    => 'Unrelated rerender body',
);
my $ditemid           = $entry->ditemid;
my $unrelated_ditemid = $unrelated->ditemid;
my $post              = {
    subject               => 'Legacy retry subject',
    event                 => 'Legacy retry body',
    security              => 'private',
    date_ymd_mm           => '02',
    date_ymd_dd           => '03',
    date_ymd_yyyy         => '2020',
    hour                  => '04',
    min                   => '05',
    date_diff             => 1,
    prop_taglist          => 'legacy-one, legacy-two',
    prop_current_location => 'Legacy retry location',
    prop_current_music    => 'Legacy retry music',
    prop_opt_backdated    => 1,
    prop_opt_preformatted => 1,
};
my $prepared = DW::Entry::Legacy::prepare_entry_form( {}, $post );
my $errors   = DW::FormErrors->new;
$errors->add_string( undef, 'Legacy retry visible error' );

DW::Request->reset;
my $request = DW::Request::Standard->new(
    GET 'http://localhost/editjournal?encoded=one%2Ftwo&repeat=first&repeat=second' );
$request->header_in( Host => 'localhost' );
my $result = DW::Controller::Entry::legacy_owned_edit_rerender(
    entry    => $entry,
    remote   => $owner,
    journal  => $owner,
    prepared => $prepared,
    errors   => $errors,
);
is( $result, $request->OK, 'callable rerender returns the real request status' );

my $content = $request->response_content;
like(
    $content,
    qr/Legacy retry visible error/,
    'real rendered retry response displays supplied errors'
);
my $form = edit_form($content);
ok( $form, 'real rendered retry response contains the native owned-edit form' )
    or BAIL_OUT('owned edit form missing from rerender');
my $expected_action =
      'http://localhost/entry/'
    . $owner->user . '/'
    . $ditemid
    . '/edit?encoded=one%2Ftwo&repeat=first&repeat=second';
is( $form->action, $expected_action,
    'rerender action targets the modern owned-edit URL and preserves raw encoded/repeated query' );
is( $form->value('subject'), 'Legacy retry subject', 'rerender retains submitted legacy subject' );
is( $form->value('event'),   'Legacy retry body',    'rerender retains submitted legacy body' );
is( $form->value('taglist'), 'legacy-one, legacy-two', 'rerender retains submitted legacy tags' );
is(
    $form->value('current_location'),
    'Legacy retry location',
    'rerender retains submitted legacy location'
);
is( $form->value('current_music'), 'Legacy retry music',
    'rerender retains submitted legacy music' );
is( $form->value('editor'),         'html_raw0',  'rerender maps retained legacy raw editor mode' );
is( $form->value('security'),       'private',    'rerender maps retained legacy security' );
is( $form->value('entrytime_date'), '2020-02-03', 'rerender retains submitted legacy date' );
is( $form->value('entrytime_time'), '04:05',      'rerender retains submitted legacy time' );
is( $form->value('entrytime_outoforder'), 1, 'rerender retains submitted backdating metadata' );

my $invalid_post = {
    %$post,
    date_ymd_yyyy => 'not-a-year',
    date_ymd_mm   => '02',
    date_ymd_dd   => '03',
    hour          => 'not-hour',
    min           => 'not-minute',
};
my $invalid_prepared = DW::Entry::Legacy::prepare_entry_form( {}, $invalid_post );
DW::Request->reset;
my $invalid_request = DW::Request::Standard->new( GET 'http://localhost/editjournal' );
$invalid_request->header_in( Host => 'localhost' );
my $invalid_result = DW::Controller::Entry::legacy_owned_edit_rerender(
    entry    => $entry,
    remote   => $owner,
    journal  => $owner,
    prepared => $invalid_prepared,
    errors   => $errors,
);
is( $invalid_result, $invalid_request->OK, 'invalid legacy date retry renders normally' );
my $invalid_form = edit_form( $invalid_request->response_content );
ok( $invalid_form, 'invalid legacy date retry contains the native owned-edit form' )
    or BAIL_OUT('owned edit form missing from invalid date rerender');
is( $invalid_form->value('entrytime_date'),
    'not-a-year-02-03', 'rerender retains the raw invalid legacy date text' );
is( $invalid_form->value('entrytime_time'),
    'not-hour:not-minute', 'rerender retains the raw invalid legacy time text' );

my $fresh = fresh_entry( $owner, $ditemid );
is(
    $fresh->subject_raw,
    'Owned rerender original subject',
    'rerender preserves the resolved entry subject'
);
is(
    $fresh->event_raw,
    'Owned rerender original body',
    'rerender preserves the resolved entry body'
);
my $fresh_unrelated = fresh_entry( $owner, $unrelated_ditemid );
is(
    $fresh_unrelated->subject_raw,
    'Unrelated rerender subject',
    'rerender preserves unrelated persisted entries'
);
is(
    $fresh_unrelated->event_raw,
    'Unrelated rerender body',
    'rerender does not modify unrelated persisted entry bodies'
);

DW::Request->reset;
done_testing;
