#!/usr/bin/perl
#
# t/plack-entry-spellcheck.t
#
# Exercise configured native editor spellcheck without saving an entry.
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
use LJ::SpellCheck;
use LJ::Test qw(temp_comm temp_user);

plan skip_all => 'Entry integration requires a development server' unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub entry_form {
    return (
        grep {
                   ( $_->attr('id') || '' ) eq 'js-post-entry'
                && $_->find_input('subject')
                && $_->find_input('event')
        } HTML::Form->parse( $_[0], 'http://localhost/entry/new' )
    )[0];
}

sub fresh_entry {
    my ( $user, $ditemid ) = @_;
    LJ::Entry::reset_singletons();
    return LJ::Entry->new( $user, ditemid => $ditemid );
}

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $owner_id  = $owner->id;
my $community = temp_comm();
LJ::set_rel( $community, $owner, 'P' );
ok( $owner->can_post_to($community), 'disposable owner can post to the selected community' );
my $entry = $owner->t_post_fake_entry(
    subject  => 'Stored spellcheck subject',
    body     => 'Stored spellcheck body',
    security => 'private',
);
my $session = LJ::Session->create( $owner, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'nativeSpellcheck';
local $LJ::SPELLER                    = 'local-stub';
my @checked;
my $hooks = 0;
no warnings 'redefine';
local *LJ::SpellCheck::check_html = sub {
    my ( $self, $body ) = @_;
    push @checked, $$body;
    return $$body =~ /misspell/ ? '<em class="spell-suggestion">suggestion</em>' : '';
};
local $LJ::HOOKS{spam_check} = [ sub { $hooks++ } ];

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    my $new_path = '/entry/new';
    my $res      = $request->( GET $new_path );
    is( $res->code, 200, 'native new form renders' );
    my $form = entry_form( $res->content );
    ok( $form, 'native new form parses' ) or BAIL_OUT('missing new form');
    ok( $form->find_input('action:spellcheck'),
        'configured editable new form has spellcheck submit' );

    my ($entries_before) =
        $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $owner_id );
    $form->action("http://localhost$new_path");
    $form->value( subject          => 'Spellcheck new subject' );
    $form->value( event            => 'misspell <b>new body</b>' );
    $form->value( taglist          => 'spell-one, spell-two' );
    $form->value( current_location => 'Spellcheck location' );
    $form->value( current_music    => 'Spellcheck music' );
    $form->value( editor           => 'html_raw0' );
    $form->value( security         => 'private' );
    $res = $request->( $form->click('action:spellcheck') );
    is( $res->code, 200, 'new spellcheck rerenders form' );
    like( $res->content, qr/spell-suggestion/,     'new spellcheck shows trusted checker result' );
    like( $res->content, qr/Spell-checked entry:/, 'new spellcheck shows global result heading' );
    $form = entry_form( $res->content );
    is( $form->value('subject'), 'Spellcheck new subject',   'new spellcheck retains subject' );
    is( $form->value('event'),   'misspell <b>new body</b>', 'new spellcheck retains body' );
    is( $form->value('taglist'), 'spell-one, spell-two',     'new spellcheck retains tags' );
    is( $form->value('current_location'), 'Spellcheck location',
        'new spellcheck retains location' );
    is( $form->value('current_music'), 'Spellcheck music', 'new spellcheck retains music' );
    is( $form->value('editor'),        'html_raw0',        'new spellcheck retains editor' );
    is(
        $checked[-1],
        'misspell &lt;b&gt;new body&lt;/b&gt;',
        'checker receives escaped submitted body'
    );
    my ($entries_after) =
        $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $owner_id );
    is( $entries_after, $entries_before, 'new spellcheck creates no entry' );
    is( $hooks, 0, 'new spellcheck skips persistence spam hooks' );

    my $community_path = $new_path . '?usejournal=' . $community->user;
    $res  = $request->( GET $community_path );
    $form = entry_form( $res->content );
    $form->action( 'http://localhost' . $community_path );
    $form->value( usejournal => $community->user );
    $form->value( subject    => 'Readonly selected community subject' );
    $form->value( event      => 'misspell readonly selected community body' );

    my $readonly               = \&LJ::User::readonly;
    my $checks_before_readonly = scalar @checked;
    {
        no warnings 'redefine';
        local *LJ::User::readonly = sub {
            return 1 if $_[0]->id == $community->id;
            return $readonly->(@_);
        };
        $res = $request->( $form->click('action:spellcheck') );
    }
    is( scalar @checked,
        $checks_before_readonly, 'readonly selected community never invokes checker' );
    my ($readonly_count) =
        $community->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?',
        undef, $community->id );
    is( $readonly_count, 0, 'readonly selected community remains unchanged' );

    $res = $request->( GET '/entry/' . $owner->user . '/' . $entry->ditemid . '/edit' );
    is( $res->code, 200, 'owned native edit form renders' );
    $form = entry_form( $res->content );
    ok( $form->find_input('action:spellcheck'),
        'configured editable edit form has spellcheck submit' );
    my $hooks_before_edit_spellcheck = $hooks;

    $form->action( 'http://localhost/entry/' . $owner->user . '/' . $entry->ditemid . '/edit' );
    $form->value( subject => 'Spellcheck edit subject' );
    $form->value( event   => 'misspell edit body' );
    $res = $request->( $form->click('action:spellcheck') );
    like( $res->content, qr/spell-suggestion/, 'edit spellcheck shows suggestions' );
    is( $checked[-1], 'misspell edit body', 'edit checker receives submitted body' );
    my $fresh = fresh_entry( $owner, $entry->ditemid );
    is(
        $fresh->subject_raw,
        'Stored spellcheck subject',
        'edit spellcheck leaves subject unchanged'
    );
    is( $fresh->event_raw, 'Stored spellcheck body', 'edit spellcheck leaves body unchanged' );
    is( $hooks, $hooks_before_edit_spellcheck, 'edit spellcheck skips persistence spam hooks' );

    $res  = $request->( GET $new_path );
    $form = entry_form( $res->content );
    $form->action("http://localhost$new_path");
    $form->value( event        => 'invalid token body' );
    $form->value( lj_form_auth => 'invalid-token' );
    my $checks_before = scalar @checked;
    $res = $request->( $form->click('action:spellcheck') );
    like( $res->content, qr/invalid form/i, 'invalid token gets native form error' );
    is( scalar @checked, $checks_before, 'invalid token never invokes checker' );
};

done_testing;
