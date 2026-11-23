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

my $old = $owner->t_post_fake_entry( subject => 'Old editor entry', body => '<p>old</p>' );
$old->set_prop( editor => 'rte0' );
my $plain = $owner->t_post_fake_entry( subject => 'Plain entry', body => '<p>plain</p>' );
$plain->set_prop( editor => 'html_raw0' );

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

        $form = edit_form( $request->( GET $path->($plain) . $mode )->content );
        is( $form->value('editor'), 'html_raw0', "$label: other entries keep their format" );
        is( $form->value('rte0_converted'), 0, "$label: and aren't flagged" );
    }

    is( fresh_entry( $owner, $old->ditemid )->prop('editor'),
        'rte0', 'opening the old entry does not rewrite its stored format' );

    my $form = edit_form( $request->( GET $path->($old) )->content );
    $form->action( 'http://localhost' . $path->($old) );
    $request->( $form->click('action:post') );
    is( fresh_entry( $owner, $old->ditemid )->prop('editor'),
        'rte1', 'saving stores the entry in the editor it was converted to' );
};

done_testing();
