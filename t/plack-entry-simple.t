#!/usr/bin/perl
#
# t/plack-entry-simple.t
#
# Simple mode of the entry form: old /update and /editjournal links open it,
# and posting, editing and deleting through its fields store the same entry
# data as the advanced form.
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
use HTML::Form;
use HTTP::Request::Common;
use Plack::Test;
use URI;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }

use LJ::Entry;
use LJ::Session;
use LJ::Test qw(temp_user);

plan skip_all => 'Entry integration requires a development server' unless $LJ::IS_DEV_SERVER;

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

sub simple_form {
    my ( $content, $base ) = @_;
    return (
        grep {
                   ( $_->attr('id') // '' ) eq 'js-post-entry'
                && ( $_->attr('class') // '' ) =~ /\bentry-simple\b/
        } HTML::Form->parse( $content, $base )
    )[0];
}

sub latest_entry {
    my ($u) = @_;
    my $fresh = LJ::load_userid( $u->id, 1 );
    my ($jitemid) = $fresh->selectrow_array( 'SELECT MAX(jitemid) FROM log2 WHERE journalid=?',
        undef, $fresh->id );
    LJ::Entry::reset_singletons();
    return $jitemid ? LJ::Entry->new( $fresh, jitemid => $jitemid ) : undef;
}

my $owner = temp_user();
$owner->update_self( { status => 'A' } );
my $session = LJ::Session->create( $owner, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entrySimple';

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    my ( $edit_location, $entry );

    subtest 'an old posting link opens simple mode, which posts the full entry' => sub {
        my $res = $request->( GET '/update.bml?subject=Simple+subject' );
        is( $res->code, 302, 'the retired posting page redirects' );
        my $location = URI->new( $res->header('Location') );
        my %query    = $location->query_form;
        is( $location->path, '/entry/new',     'to the native new-entry form' );
        is( $query{mode},    'simple',         'in its simple layout' );
        is( $query{subject}, 'Simple subject', 'carrying the prefilled subject' );

        $res = $request->( GET $location->path_query );
        my $form = simple_form( $res->content, "http://localhost" . $location->path_query );
        ok( $form, 'the simple form renders' ) or return;
        is( $form->value('subject'), 'Simple subject', 'with the subject prefilled' );

        $form->value( event            => 'Simple mode body' );
        $form->value( editor           => 'html_raw0' );
        $form->value( taglist          => 'simple tag' );
        $form->value( current_music    => 'Simple music' );
        $form->value( comment_settings => 'noemail' );
        $form->value( security         => 'private' );
        $res = $request->( $form->click('action:post') );
        is( $res->code, 200, 'posting returns the success page' );

        $entry = latest_entry($owner);
        ok( $entry, 'the entry was created' ) or return;
        is( $entry->subject_raw,           'Simple subject',   'subject stored' );
        is( $entry->event_raw,             'Simple mode body', 'body stored' );
        is( $entry->security,              'private',          'security stored' );
        is( $entry->prop('current_music'), 'Simple music',     'music stored' );
        is( $entry->prop('opt_noemail'),   1,                  'comment setting stored' );
        is( join( ',', $entry->tags ), 'simple tag', 'tags stored' );

        ($edit_location) = $res->content =~ m{href="([^"]*/entry/[^"/]+/\d+/edit[^"]*)"};
        like( $edit_location // '',
            qr/\bmode=simple\b/, 'the success page edits the entry in simple mode too' );
    };

    subtest 'an old edit link opens simple mode, which saves and deletes the entry' => sub {
        plan skip_all => 'no entry to edit' unless $entry;

        my $res = $request->( GET '/editjournal.bml?itemid=' . $entry->ditemid );
        is( $res->code, 302, 'the retired edit link redirects' );
        my $location = URI->new( $res->header('Location') );
        is(
            $location->path,
            '/entry/' . $owner->user . '/' . $entry->ditemid . '/edit',
            'to the native edit form'
        );
        is( { $location->query_form }->{mode}, 'simple', 'in its simple layout' );

        $res = $request->( GET $location->path_query );
        my $form = simple_form( $res->content, "http://localhost" . $location->path_query );
        ok( $form, 'the simple edit form renders' ) or return;
        is( $form->value('event'), 'Simple mode body', 'with the stored body' );

        $form->value( subject => 'Simple subject, edited' );
        $res = $request->( $form->click('action:post') );
        is( $res->code, 200, 'saving returns the success page' );
        my $edited = latest_entry($owner);
        is( $edited->subject_raw, 'Simple subject, edited', 'the edited subject is stored' );
        is( $edited->event_raw,   'Simple mode body',       'the body is unchanged' );

        $res  = $request->( GET $location->path_query );
        $form = simple_form( $res->content, "http://localhost" . $location->path_query );
        $res  = $request->( $form->click('action:delete') );
        is( $res->code,           200,   'deleting returns the success page' );
        is( latest_entry($owner), undef, 'the entry is gone' );
    };
};

done_testing;
