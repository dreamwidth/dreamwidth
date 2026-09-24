#!/usr/bin/perl
#
# t/plack-entry-new-parity.t
#
# Characterize ordinary owned private-entry creation through the native form.
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
use Storable qw(nfreeze thaw);

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Entry;
use LJ::Session;
use LJ::Test qw(temp_user);

plan skip_all => 'Entry integration requires a development server' unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub new_entry_form {
    my ($content) = @_;
    return (
        grep {
                   $_->attr('id')
                && $_->attr('id') eq 'js-post-entry'
                && $_->find_input('subject')
                && $_->find_input('event')
        } HTML::Form->parse( $content, 'http://localhost/entry/new' )
    )[0];
}

sub fresh_user {
    my ($userid) = @_;
    return LJ::load_userid( $userid, 1 );
}

sub fresh_draft_properties {
    my ($user) = @_;
    my $frozen = $user->prop('draft_properties') || '';
    return {} unless length $frozen;
    return Storable::thaw($frozen);
}

sub sorted_tags {
    my ($taglist) = @_;
    return [ sort grep { length } map { s/^\s+|\s+$//gr } split /,/, $taglist // '' ];
}

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $owner_id = $owner->id;
my $session  = LJ::Session->create( $owner, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryNewParity';

ok( $owner->set_draft_text('Saved draft body that successful post must clear'),
    'seeded disposable owner draft body' );
$owner->set_prop(
    'draft_properties',
    nfreeze(
        {
            subject   => 'Saved draft subject',
            editor    => 'markdown0',
            taglist   => 'saved-draft-tag',
            location1 => 'Saved draft location',
            music     => 'Saved draft music',
        }
    )
);

my ($entries_before) =
    $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $owner_id );
is( $entries_before, 0, 'disposable owner begins with no entries' );

my $fresh_seed = fresh_user($owner_id);
is(
    $fresh_seed->draft_text,
    'Saved draft body that successful post must clear',
    'forced-fresh owner exposes the seeded draft body'
);
is_deeply(
    fresh_draft_properties($fresh_seed),
    {
        subject   => 'Saved draft subject',
        editor    => 'markdown0',
        taglist   => 'saved-draft-tag',
        location1 => 'Saved draft location',
        music     => 'Saved draft music',
    },
    'forced-fresh owner exposes the seeded draft properties'
);

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    my $res = $request->( GET '/entry/new' );
    is( $res->code, 200, 'authenticated owner receives the native new-entry form' );
    my $form = new_entry_form( $res->content );
    ok( $form, 'actual native new-entry form parses' ) or BAIL_OUT('new-entry form missing');

    for my $name (
        qw(subject event editor security taglist current_location current_music lj_form_auth))
    {
        ok( $form->find_input($name), "rendered new-entry form contains $name" );
    }
    my @editor_values = $form->find_input('editor')->possible_values;
    ok( scalar grep { $_ eq 'html_raw0' } @editor_values,
        'native form offers raw HTML editor for an exact ordinary save' );

    $form->action('http://localhost/entry/new');
    $form->value( subject          => 'New entry parity distinct subject' );
    $form->value( event            => '<p>New entry parity distinct body</p>' );
    $form->value( editor           => 'html_raw0' );
    $form->value( security         => 'private' );
    $form->value( taglist          => 'new-entry-one, new-entry-two' );
    $form->value( current_location => 'New entry parity location' );
    $form->value( current_music    => 'New entry parity music' );
    $res = $request->( $form->click('action:post') );

    is( $res->code, 200, 'actual private new-entry post returns a success page' );
    like(
        $res->content,
        qr/(?:Entry Posted|entry was posted|successfully)/i,
        'successful post has a meaningful success body'
    );

    my $fresh_owner = fresh_user($owner_id);
    my ($entries_after) =
        $fresh_owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?',
        undef, $owner_id );
    is( $entries_after, $entries_before + 1, 'successful form submit creates exactly one entry' );

    my ($jitemid) = $fresh_owner->selectrow_array(
        'SELECT jitemid FROM log2 WHERE journalid=? ORDER BY jitemid DESC LIMIT 1',
        undef, $owner_id );
    ok( $jitemid, 'newly persisted entry has an item id' );
    LJ::Entry::reset_singletons();
    my $entry = LJ::Entry->new( $fresh_owner, jitemid => $jitemid );
    ok( $entry, 'forced-fresh newly persisted entry loads' ) or BAIL_OUT('new entry unavailable');
    is( $entry->security, 'private', 'new entry persists private security' );
    is(
        $entry->subject_raw,
        'New entry parity distinct subject',
        'new entry persists exact subject'
    );
    is(
        $entry->event_raw,
        '<p>New entry parity distinct body</p>',
        'new entry persists exact body'
    );
    is_deeply(
        [ sort $entry->tags ],
        [ 'new-entry-one', 'new-entry-two' ],
        'new entry persists exact tag set'
    );
    is( $entry->prop('editor'), 'html_raw0', 'new entry persists the selected editor' );
    is(
        $entry->prop('current_location'),
        'New entry parity location',
        'new entry persists location'
    );
    is( $entry->prop('current_music'), 'New entry parity music', 'new entry persists music' );

    $fresh_owner = fresh_user($owner_id);
    is( $fresh_owner->draft_text, undef,
        'successful post clears the saved draft body (stored empty draft reads back as undef)' );
    is_deeply( fresh_draft_properties($fresh_owner),
        {}, 'successful post clears saved draft properties' );

    my $edit_path = '/entry/' . $owner->user . '/' . $entry->ditemid . '/edit';
    $res = $request->( GET $edit_path );
    is( $res->code, 200, 'fresh edit GET renders the newly created private entry for its owner' );
    $form = new_entry_form( $res->content );
    ok( $form, 'fresh edit response uses the same real entry form' )
        or BAIL_OUT('fresh edit form missing');
    is(
        $form->value('subject'),
        'New entry parity distinct subject',
        'fresh edit form renders persisted subject exactly'
    );
    is(
        $form->value('event'),
        '<p>New entry parity distinct body</p>',
        'fresh edit form renders persisted body exactly'
    );
    is( $form->value('editor'), 'html_raw0', 'fresh edit form selects persisted editor' );
    is( $form->value('security'), 'private', 'fresh edit form selects persisted private security' );
    is_deeply(
        sorted_tags( $form->value('taglist') ),
        [ 'new-entry-one', 'new-entry-two' ],
        'fresh edit form renders persisted tags'
    );
    is(
        $form->value('current_location'),
        'New entry parity location',
        'fresh edit form renders persisted location'
    );
    is(
        $form->value('current_music'),
        'New entry parity music',
        'fresh edit form renders persisted music'
    );
};

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    # An unresolvable usejournal must render translated error text, not a
    # missing-string placeholder.
    my $res = $request->( GET '/entry/new?usejournal=entry-new-parity-nonexistent-user' );
    is( $res->code, 200, 'GET with an unresolvable usejournal still renders the new-entry form' );
    ( my $text = $res->content ) =~ s/<[^>]+>//g;
    like(
        $text,
        qr/Invalid usejournal argument/,
        'invalid usejournal error renders its real translated text'
    );
    unlike(
        $res->content,
        qr/\[missing string/,
        'invalid usejournal error is not an unresolved missing-string placeholder'
    );
};

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    my ($entries_before) =
        $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $owner_id );

    my $res  = $request->( GET '/entry/new' );
    my $form = new_entry_form( $res->content );
    ok( $form, 'actual native new-entry form parses' ) or BAIL_OUT('new-entry form missing');
    $form->action('http://localhost/entry/new');
    $form->value( subject => 'Empty body retained title' );
    $form->value( event   => '' );
    $res = $request->( $form->click('action:post') );

    is( $res->code, 200, 'empty-body post re-renders the form instead of erroring' );
    my $error_count = () = $res->content =~ /Must provide entry text/ig;
    is( $error_count, 1, 'empty-body validation renders exactly one error' );
    unlike(
        $res->content,
        qr/\[missing string|error\.noentry/,
        'empty-body response exposes no missing-string banner or raw key'
    );
    like(
        $res->content,
        qr/Empty body retained title/,
        'empty-body response retains submitted title'
    );

    my ($entries_after) =
        $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $owner_id );
    is( $entries_after, $entries_before, 'empty-body post creates no entry' );
};

done_testing;
