#!/usr/bin/perl
# Characterize owned private-entry editor mode roundtrips before editor rendering migration.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.

use strict;
use warnings;

use Test::More;
use HTTP::Request::Common;
use HTML::Form;
use Plack::Test;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Entry;
use LJ::MemCache;
use LJ::Session;
use LJ::Test qw(temp_user);

plan skip_all => 'Entry integration requires a development server' unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub edit_form {
    my ($content) = @_;
    return (
        grep { $_->find_input('subject') && $_->find_input('event') && $_->find_input('editor') }
            HTML::Form->parse( $content, 'http://localhost' ) )[0];
}

sub fresh_entry {
    my ( $owner, $ditemid ) = @_;
    LJ::Entry::reset_singletons();
    return LJ::Entry->new( $owner, ditemid => $ditemid );
}

sub replace_fixture_body {
    my ( $entry, $subject, $body ) = @_;
    my $owner  = $entry->journal;
    my $itemid = $entry->jitemid;
    my $ok     = $owner->do(
        'UPDATE logtext2 SET subject=?, event=? WHERE journalid=? AND jitemid=?',
        undef, $subject, LJ::text_compress($body),
        $owner->id, $itemid
    );
    die 'unable to replace legacy Markdown fixture text' unless $ok;
    LJ::MemCache::set(
        [ $owner->id, "logtext:" . $owner->clusterid . ':' . $owner->id . ":$itemid" ],
        [ $subject,   $body ] );
    LJ::Entry::reset_singletons();
}

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $session = LJ::Session->create( $owner, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryEditModes';

my @modes = (
    {
        name          => 'casual HTML',
        editor        => 'html_casual1',
        original      => '<strong>casual original</strong>',
        no_op_body    => '<strong>casual original</strong>',
        changed_input => '<strong>casual changed</strong>',
        changed_body  => '<strong>casual changed</strong>',
    },
    {
        name          => 'raw HTML',
        editor        => 'html_raw0',
        original      => '<i>raw original</i>',
        no_op_body    => '<i>raw original</i>',
        changed_input => '<i>raw changed</i>',
        changed_body  => '<i>raw changed</i>',
    },
    {
        name          => 'Markdown',
        editor        => 'markdown0',
        original      => '*markdown original*',
        no_op_body    => '*markdown original*',
        changed_input => '*markdown changed*',
        changed_body  => '*markdown changed*',
    },
    {
        name            => 'legacy Markdown detection',
        editor          => undef,
        original        => "!markdown\n*legacy original*",
        rendered_editor => 'markdown0',
        no_op_body      => '*legacy original*',
        changed_input   => '*legacy changed*',
        changed_body    => '*legacy changed*',
        legacy          => 1,
    },
    {
        name          => 'Rich Text Editor',
        editor        => 'rte0',
        original      => '<p>RTE original</p>',
        no_op_body    => '<p>RTE original</p>',
        changed_input => '<p>RTE changed</p>',
        changed_body  => '<p>RTE changed</p>',
    },
);

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    for my $mode (@modes) {
        my $entry = $owner->t_post_fake_entry(
            subject  => "$mode->{name} original subject",
            body     => $mode->{legacy} ? 'temporary legacy body' : $mode->{original},
            security => 'private',
        );
        $entry->set_prop( editor => $mode->{editor} ) if defined $mode->{editor};
        if ( $mode->{legacy} ) {
            replace_fixture_body( $entry, "$mode->{name} original subject", $mode->{original} );
            $entry = fresh_entry( $owner, $entry->ditemid );
            ok( !defined $entry->prop('editor'), "$mode->{name} fixture has no editor prop" );
        }

        my $path = '/entry/' . $owner->user . '/' . $entry->ditemid . '/edit';
        my $res  = $request->( GET $path );
        is( $res->code, 200, "$mode->{name} private entry renders for its owner" );
        my $form = edit_form( $res->content );
        ok( $form, "$mode->{name} has an actual owned-entry edit form" ) or next;
        is( $form->value('security'),
            'private', "$mode->{name} rendered form retains private security" );
        is(
            $form->value('editor'),
            $mode->{rendered_editor} || $mode->{editor},
            "$mode->{name} rendered form selects its active editor"
        );

        my $rendered_subject = $form->value('subject');
        my $rendered_body    = $form->value('event');
        $form->action( 'http://localhost' . $path );
        $res = $request->( $form->click('action:post') );
        is( $res->code, 200, "$mode->{name} actual no-op submit succeeds" );

        my $fresh = fresh_entry( $owner, $entry->ditemid );
        is( $fresh->subject_raw, $rendered_subject,
            "$mode->{name} no-op preserves subject exactly" );
        is( $fresh->event_raw, $mode->{no_op_body},
            "$mode->{name} no-op persists expected body exactly" );
        is(
            $fresh->prop('editor'),
            $mode->{rendered_editor} || $mode->{editor},
            "$mode->{name} no-op persists the selected editor prop"
        );

        $res  = $request->( GET $path );
        $form = edit_form( $res->content );
        is(
            $form->value('editor'),
            $mode->{rendered_editor} || $mode->{editor},
            "$mode->{name} fresh form retains selected editor"
        );
        $form->action( 'http://localhost' . $path );
        $form->value( event => $mode->{changed_input} );
        $res = $request->( $form->click('action:post') );
        is( $res->code, 200, "$mode->{name} actual changed-content submit succeeds" );

        $fresh = fresh_entry( $owner, $entry->ditemid );
        is( $fresh->event_raw, $mode->{changed_body},
            "$mode->{name} persists changed body exactly" );
        is(
            $fresh->prop('editor'),
            $mode->{rendered_editor} || $mode->{editor},
            "$mode->{name} retains editor prop after changed content"
        );
    }
};

done_testing;
