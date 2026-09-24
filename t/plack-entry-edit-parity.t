#!/usr/bin/perl
# Characterize ordinary owned-entry edit form persistence before editor rendering migration.
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
use LJ::Userpic;

plan skip_all => 'Entry integration requires a development server' unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub file_contents {
    my ($path) = @_;
    open my $fh, '<', $path or die "open $path: $!";
    binmode $fh;
    local $/;
    my $contents = <$fh>;
    return \$contents;
}

sub forms {
    return HTML::Form->parse( $_[0], 'http://localhost' );
}

sub edit_form {
    my ($content) = @_;
    return ( grep { $_->find_input('subject') && $_->find_input('event') } forms($content) )[0];
}

sub sorted_tags {
    my ($taglist) = @_;
    return [ sort grep { length } map { s/^\s+|\s+$//gr } split /,/, $taglist // '' ];
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
my $userpic =
    LJ::Userpic->create( $owner, data => file_contents("$ENV{LJHOME}/t/data/userpics/good.jpg"), );
ok( $userpic, 'disposable owner userpic is created' )
    or BAIL_OUT('cannot exercise userpic control');
$userpic->set_keywords('editor-parity-pic');

my $session = LJ::Session->create( $owner, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryEditParity';

my $path = '/entry/' . $owner->user . '/' . $ditemid . '/edit';

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    my $res = $request->( GET $path );
    is( $res->code, 200, 'authenticated owner receives the native edit form' );
    my $form = edit_form( $res->content );
    ok( $form, 'actual owned-entry edit form is rendered' ) or BAIL_OUT('edit form missing');

    for my $name (
        qw(subject event taglist current_location current_music prop_picture_keyword lj_form_auth))
    {
        ok( $form->find_input($name), "rendered form contains $name" );
    }

    $form->action( 'http://localhost' . $path );
    $form->value( subject              => 'Editor parity changed subject' );
    $form->value( event                => 'Editor parity changed body' );
    $form->value( taglist              => 'editor-one, editor-two' );
    $form->value( current_location     => 'Editor parity location' );
    $form->value( current_music        => 'Editor parity music' );
    $form->value( prop_picture_keyword => 'editor-parity-pic' );
    $res = $request->( $form->click('action:post') );
    is( $res->code, 200, 'actual save control rerenders the populated owned-entry form' );

    my $fresh = fresh_entry( $owner, $ditemid );
    is(
        $fresh->subject_raw,
        'Editor parity changed subject',
        'fresh entry persists changed subject'
    );
    is( $fresh->event_raw, 'Editor parity changed body', 'fresh entry persists changed body' );
    is_deeply(
        [ sort $fresh->tags ],
        [ 'editor-one', 'editor-two' ],
        'fresh entry persists changed tags'
    );
    is(
        $fresh->prop('current_location'),
        'Editor parity location',
        'fresh entry persists changed location'
    );
    is( $fresh->prop('current_music'), 'Editor parity music',
        'fresh entry persists changed music' );
    is( $fresh->userpic_kw, 'editor-parity-pic', 'fresh entry persists changed userpic keyword' );

    $res = $request->( GET $path );
    is( $res->code, 200, 'fresh edit GET renders after populated save' );
    $form = edit_form( $res->content );
    is(
        $form->value('subject'),
        'Editor parity changed subject',
        'fresh form selects persisted subject'
    );
    is( $form->value('event'), 'Editor parity changed body', 'fresh form selects persisted body' );
    is_deeply(
        sorted_tags( $form->value('taglist') ),
        [ 'editor-one', 'editor-two' ],
        'fresh form selects the persisted tag set'
    );
    is(
        $form->value('current_location'),
        'Editor parity location',
        'fresh form selects persisted location'
    );
    is( $form->value('current_music'), 'Editor parity music',
        'fresh form selects persisted music' );
    is( $form->value('prop_picture_keyword'),
        'editor-parity-pic', 'fresh form selects persisted userpic' );

    $form->action( 'http://localhost' . $path );
    $form->value( taglist              => '' );
    $form->value( current_location     => '' );
    $form->value( current_music        => '' );
    $form->value( prop_picture_keyword => '' );
    $res = $request->( $form->click('action:post') );
    is( $res->code, 200, 'actual save control rerenders cleared metadata values' );

    $fresh = fresh_entry( $owner, $ditemid );
    is_deeply( [ $fresh->tags ], [], 'fresh entry clears prior tags' );
    is( $fresh->prop('current_location'), undef, 'fresh entry clears prior location' );
    is( $fresh->prop('current_music'),    undef, 'fresh entry clears prior music' );
    is( $fresh->userpic_kw,               undef, 'fresh entry clears prior userpic selection' );
    is(
        $fresh->subject_raw,
        'Editor parity changed subject',
        'metadata clearing preserves subject'
    );
    is( $fresh->event_raw, 'Editor parity changed body', 'metadata clearing preserves body' );

    $res  = $request->( GET $path );
    $form = edit_form( $res->content );
    is( $form->value('taglist'),              '', 'fresh form renders cleared tags' );
    is( $form->value('current_location'),     '', 'fresh form renders cleared location' );
    is( $form->value('current_music'),        '', 'fresh form renders cleared music' );
    is( $form->value('prop_picture_keyword'), '', 'fresh form renders cleared userpic selection' );
};

done_testing;
