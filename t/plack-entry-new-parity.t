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
use Storable qw(nfreeze);

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

my @spam_checks;
local $LJ::HOOKS{spam_check} = [ sub { push @spam_checks, [@_]; return; } ];

ok( $owner->set_draft_text('Saved draft body that successful post must clear'),
    'seeded disposable owner draft body' );
$owner->set_prop( draft_properties => nfreeze( { subject => 'Saved draft subject' } ) );

test_psgi $app, sub {
    my $send    = shift;
    my $request = sub {
        my ($req) = @_;
        $req->header( Cookie => $cookie );
        return $send->($req);
    };

    my $res  = $request->( GET '/entry/new' );
    my $form = new_entry_form( $res->content );
    ok( $form, 'actual native new-entry form parses' ) or BAIL_OUT('new-entry form missing');

    $form->action('http://localhost/entry/new');
    $form->value( subject  => 'New entry parity distinct subject' );
    $form->value( event    => '<p>New entry parity distinct body</p>' );
    $form->value( editor   => 'html_raw0' );
    $form->value( security => 'private' );
    $res = $request->( $form->click('action:post') );
    is( $res->code, 200, 'private new-entry post returns a success page' );

    my $fresh_owner = LJ::load_userid( $owner_id, 1 );
    my $jitemids = $fresh_owner->selectcol_arrayref( 'SELECT jitemid FROM log2 WHERE journalid=?',
        undef, $owner_id );
    is( scalar @$jitemids, 1, 'form submit creates exactly one entry' );
    LJ::Entry::reset_singletons();
    my $entry = LJ::Entry->new( $fresh_owner, jitemid => $jitemids->[0] );
    is( $entry->security, 'private', 'new entry persists private security' );
    is(
        $entry->event_raw,
        '<p>New entry parity distinct body</p>',
        'new entry persists the raw body exactly'
    );

    is( $fresh_owner->draft_text, undef, 'successful post clears the saved draft body' );
    is( $fresh_owner->prop('draft_properties') // '',
        '', 'successful post clears saved draft properties' );
};

done_testing;
