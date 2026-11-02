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
use LJ::Test qw(temp_user);

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

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $owner_id = $owner->id;
my $entry    = $owner->t_post_fake_entry(
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
no warnings 'redefine';
local *LJ::SpellCheck::check_html = sub {
    my ( $self, $body ) = @_;
    push @checked, $$body;
    return $$body =~ /misspell/ ? '<em class="spell-suggestion">suggestion</em>' : '';
};
my @spam_checks;
local $LJ::HOOKS{spam_check} = [ sub { push @spam_checks, [@_]; return; } ];

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    my $new_path = '/entry/new';
    my $form     = entry_form( $request->( GET $new_path )->content );
    ok( $form, 'native new form parses' ) or BAIL_OUT('missing new form');
    my ($entries_before) =
        $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $owner_id );
    $form->action("http://localhost$new_path");
    $form->value( subject => 'Spellcheck new subject' );
    $form->value( event   => 'misspell <b>new body</b>' );
    my $res = $request->( $form->click('action:spellcheck') );
    like( $res->content, qr/spell-suggestion/, 'new spellcheck shows the checker result' );

    # The checker's output is rendered as trusted HTML, so its input must be escaped.
    is(
        $checked[-1],
        'misspell &lt;b&gt;new body&lt;/b&gt;',
        'checker receives escaped submitted body'
    );
    is(
        entry_form( $res->content )->value('event'),
        'misspell <b>new body</b>',
        'new spellcheck retains the submitted body'
    );
    my ($entries_after) =
        $owner->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $owner_id );
    is( $entries_after, $entries_before, 'new spellcheck creates no entry' );

    my $edit_path = '/entry/' . $owner->user . '/' . $entry->ditemid . '/edit';
    $form = entry_form( $request->( GET $edit_path )->content );
    $form->action( 'http://localhost' . $edit_path );
    $form->value( subject => 'Spellcheck edit subject' );
    $form->value( event   => 'misspell edit body' );
    $res = $request->( $form->click('action:spellcheck') );
    like( $res->content, qr/spell-suggestion/, 'edit spellcheck shows suggestions' );
    LJ::Entry::reset_singletons();
    my $fresh = LJ::Entry->new( $owner, ditemid => $entry->ditemid );
    is(
        $fresh->subject_raw,
        'Stored spellcheck subject',
        'edit spellcheck leaves subject unchanged'
    );
    is( $fresh->event_raw, 'Stored spellcheck body', 'edit spellcheck leaves body unchanged' );
};

done_testing;
