#!/usr/bin/perl
#
# t/plack-entry-rte0.t
#
# An entry stored in the retired rte0 editor format opens in the current rich
# text editor, with a warning that it was converted. Viewing it changes nothing
# stored; the format only changes when the poster saves.
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
use Storable;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::CleanHTML;
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

# What a reader would see for a body stored in the given format.
sub rendered {
    my ( $body, $editor ) = @_;
    LJ::CleanHTML::clean_event( \$body, { editor => $editor } );
    return $body;
}

sub fresh_entry {
    my ( $owner, $ditemid ) = @_;
    LJ::Entry::reset_singletons();
    return LJ::Entry->new( $owner, ditemid => $ditemid );
}

my $owner = temp_user();
$owner->update_self( { status => 'A' } );

my $old_body = "<p>old</p>\nline one\nline two http://example.com/page and \@" . $owner->user;
my $old      = $owner->t_post_fake_entry( subject => 'Old editor entry', body => $old_body );
$old->set_prop( editor => 'rte0' );
my $plain = $owner->t_post_fake_entry( subject => 'Plain entry', body => '<p>plain</p>' );
$plain->set_prop( editor => 'html_raw0' );

# A saved draft from the retired editor.
$owner->set_prop( entry_draft => "draft line a\ndraft line b" );
$owner->set_prop(
    draft_properties => Storable::nfreeze( { editor => 'rte0', subject => 'Old draft' } ) );

my $session = LJ::Session->create( $owner, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryRte0';

my $path = sub { '/entry/' . $owner->user . '/' . $_[0]->ditemid . '/edit' };

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    foreach my $mode ( '', '?mode=simple' ) {
        my $label = $mode ? 'simple layout' : 'advanced layout';

        my $form = edit_form( $request->( GET $path->($old) . $mode )->content );
        ok( $form, "$label: old-editor entry renders its edit form" ) or next;
        is( $form->value('editor'), 'rte1', "$label: opens in the rich text editor" );
        ok( !( grep { defined && $_ eq 'rte0' } $form->find_input('editor')->possible_values ),
            "$label: rte0 can no longer be chosen" );
        is( $form->value('rte0_converted'), 1, "$label: flagged as converted from rte0" );

        # No JavaScript runs here: the text the form carries is what would be
        # submitted, so it has to be explicit rte1 source already.
        is(
            rendered( $form->value('event'), 'rte1' ),
            rendered( $old_body,             'rte0' ),
            "$label: the text is converted so it reads the same as rte1"
        );

        $form = edit_form( $request->( GET $path->($plain) . $mode )->content );
        is( $form->value('editor'), 'html_raw0', "$label: other entries keep their format" );
        is( $form->value('rte0_converted'), 0, "$label: and aren't flagged" );
    }

    my $new_page = $request->( GET '/entry/new' )->content;
    like(
        $new_page,
        qr/var restoredEditor\s*=\s*"rte1"/,
        'a restored rte0 draft is restored as rte1'
    );
    like( $new_page, qr/var restoredRte0\s*=\s*true/,     '...and flagged for the warning' );
    like( $new_page, qr/draft line a<br \/>draft line b/, '...with its text already converted' );

    is( fresh_entry( $owner, $old->ditemid )->prop('editor'),
        'rte0', 'opening the old entry does not rewrite its stored format' );

    my $form = edit_form( $request->( GET $path->($old) )->content );
    $form->action( 'http://localhost' . $path->($old) );
    $request->( $form->click('action:post') );
    my $saved = fresh_entry( $owner, $old->ditemid );
    is( $saved->prop('editor'),
        'rte1', 'saving stores the entry in the editor it was converted to' );
    is(
        rendered( $saved->event_raw, 'rte1' ),
        rendered( $old_body,         'rte0' ),
        'and the saved entry reads the same as before, saved without JavaScript'
    );

    # A form left open in an old tab posts its rte0 source as rte0. That is kept
    # exactly as sent and stored as rte0, which renders as it always has; it
    # converts the next time the entry is opened for editing.
    my $stale_entry = $owner->t_post_fake_entry( subject => 'Stale tab', body => 'placeholder' );
    my $stale_path  = $path->($stale_entry);
    my $stale_body  = "stale line one\nstale line two http://example.com/";
    my $form2       = edit_form( $request->( GET $stale_path )->content );
    $form2->action( 'http://localhost' . $stale_path );
    $form2->value( event => $stale_body );
    my $post = $form2->click('action:post');
    ( my $content = $post->content ) =~ s/\beditor=\w+/editor=rte0/;
    $post->content($content);
    $post->header( 'Content-Length' => length $content );
    $request->($post);
    my $stale_saved = fresh_entry( $owner, $stale_entry->ditemid );
    is( $stale_saved->prop('editor'), 'rte0',      'a stale rte0 POST is stored as rte0' );
    is( $stale_saved->event_raw,      $stale_body, '...with its body exactly as sent' );
};

done_testing();
