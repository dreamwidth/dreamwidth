#!/usr/bin/perl
#
# t/plack-entry-crosspost.t
#
# Characterize native rendered crossposting without external delivery.
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
{

    package CrosspostFixture::Account;
    sub new { my $class = shift; bless {@_}, $class }
    sub acctid         { $_[0]{id} }
    sub displayname    { $_[0]{name} }
    sub password       { $_[0]{password} }
    sub xpostbydefault { $_[0]{default} }
}

sub form {
    ( grep { ( $_->attr('id') || '' ) eq 'js-post-entry' }
            HTML::Form->parse( $_[0], 'http://localhost/entry/new' ) )[0];
}

sub edit_form {
    ( grep { $_->find_input('subject') && $_->find_input('event') }
            HTML::Form->parse( $_[0], 'http://localhost' ) )[0];
}

my $user = temp_user();
$user->update_self( { status => 'A' } );
my $uid     = $user->id;
my $session = LJ::Session->create( $user, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
my @accounts = (
    CrosspostFixture::Account->new(
        id       => 41,
        name     => 'Selected account',
        password => '',
        default  => 1
    ),
    CrosspostFixture::Account->new(
        id       => 42,
        name     => 'Unselected account',
        password => '',
        default  => 0
    )
);
my @calls;
test_psgi $app, sub {
    my $send    = shift;
    my $request = sub { my ($r) = @_; $r->header( Cookie => $cookie ); $send->($r) };
    no warnings 'redefine';
    local *DW::External::Account::get_external_accounts = sub { @accounts };
    local *LJ::Protocol::schedule_xposts                = sub {
        my ( $poster, $ditemid, $deleted, $callback ) = @_;
        push @calls,
            [
            $poster->id, $ditemid, $deleted,
            [ map { my @value = $callback->($_); [ $_->acctid, \@value ] } @accounts ]
            ];
        return ( [ $accounts[0] ], [] );
    };
    my $res = $request->( GET '/entry/new' );
    is( $res->code, 200, 'native form renders' );
    my $f = form( $res->content );
    ok( $f, 'actual native form parses' ) or return;
    $f->value( subject         => 'Crosspost scheduler marker' );
    $f->value( event           => 'Crosspost body marker' );
    $f->value( crosspost_entry => 1 );
    $f->value( crosspost       => 41 );
    $res = $request->( $f->click('action:post') );
    is( $res->code,    200,  'real form post succeeds' );
    is( scalar @calls, 1,    'successful own-journal enabled post schedules exactly once' );
    is( $calls[0][0],  $uid, 'scheduler receives exact poster' );
    is( $calls[0][2],  0,    'new post scheduler is not deletion' );
    is_deeply(
        $calls[0][3],
        [
            [ 41, [ 1, { password => '',    auth_challenge => '',    auth_response => '' } ] ],
            [ 42, [ 0, { password => undef, auth_challenge => undef, auth_response => undef } ] ],
        ],
        'scheduler callback preserves selected and unselected account state'
    );
    my ($count) =
        $user->selectrow_array( 'SELECT COUNT(*) FROM log2 WHERE journalid=?', undef, $uid );
    is( $count, 1, 'real form persists one entry' );

    my ( $jitemid, $anum ) = $user->selectrow_array(
        'SELECT jitemid, anum FROM log2 WHERE journalid=? ORDER BY jitemid ASC LIMIT 1',
        undef, $uid );
    my $edit_path = '/entry/' . $user->user . '/' . ( $jitemid * 256 + $anum ) . '/edit';
    @calls = ();
    $res   = $request->( GET $edit_path );
    is( $res->code, 200, 'native owned-entry edit form renders' );
    my $edit = edit_form( $res->content );
    ok( $edit, 'native owned-entry edit form parses' ) or return;
    $edit->action( 'http://localhost' . $edit_path );
    $edit->value( subject         => 'Native edit crosspost subject' );
    $edit->value( event           => 'Native edit crosspost body' );
    $edit->value( crosspost_entry => 1 );
    $edit->value( crosspost       => 41 );
    $res = $request->( $edit->click('action:post') );
    is( $res->code,    200, 'native owned-entry edit succeeds' );
    is( scalar @calls, 1,   'native owned-entry edit schedules exactly once' );
    is( $calls[0][2],  0,   'native owned-entry edit uses non-delete scheduler state' );
    is_deeply(
        $calls[0][3],
        [
            [ 41, [ 1, { password => '',    auth_challenge => '',    auth_response => '' } ] ],
            [ 42, [ 0, { password => undef, auth_challenge => undef, auth_response => undef } ] ],
        ],
        'native owned-entry edit callback preserves selected and unselected values'
    );
};
done_testing;
