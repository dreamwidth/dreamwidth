#!/usr/bin/perl
# Owned private-entry display-date and backdating regression coverage.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use HTML::Form;
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user);
plan skip_all => 'Entry rendering integration requires a development server'
    unless $LJ::IS_DEV_SERVER;
my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';
my $u = temp_user();
$u->update_self( { status => 'A' } );
my %posted;
LJ::do_request(
    {
        mode     => 'postevent',
        ver      => $LJ::PROTOCOL_VER,
        user     => $u->user,
        subject  => 'Timestamp title',
        event    => 'Timestamp body',
        year     => 2020,
        mon      => 1,
        day      => 2,
        hour     => 3,
        min      => 4,
        security => 'private'
    },
    \%posted,
    { noauth => 1, nomod => 1 }
);
die "fixture entry failed: $posted{errmsg}" unless $posted{success} eq 'OK';
my $ditemid = ( $posted{itemid} << 8 ) + $posted{anum};
my $session = LJ::Session->create( $u, nolog => 1 );
my $cookie =
      'ljmastersession='
    . $session->master_cookie_string
    . '; ljloggedin='
    . $session->loggedin_cookie_string;
local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'entryRenderingParity';
my $path = '/entry/' . $u->user . "/$ditemid/edit";
test_psgi $app, sub {
    my $send = shift;
    my $cb   = sub { my $req = shift; $req->header( Cookie => $cookie ); return $send->($req) };
    my $res  = $cb->( GET $path);
    is( $res->code, 200, 'owned entry edit form renders' );
    like( $res->content, qr/value=["']2020-01-02["']/, 'existing entry date loads' );
    like( $res->content, qr/value=["']03:04["']/,      'existing entry time loads' );
    my ($form) = grep { ( ( $_->attr('id') || '' ) eq 'js-post-entry' ) }
        HTML::Form->parse( $res->content, 'http://localhost' . $path );
    ok( $form, 'actual edit form parses' ) or return;
    $form->value( 'entrytime_date',       '2021-02-03' );
    $form->value( 'entrytime_time',       '04:05' );
    $form->value( 'entrytime_outoforder', '1' );
    my $request = $form->click;
    $request->uri( 'http://localhost' . $path );
    $res = $cb->($request);
    is( $res->code, 200, 'distinct timestamp save succeeds' );
    LJ::Entry::reset_singletons();
    my $fresh = LJ::Entry->new( $u, ditemid => $ditemid );
    is( $fresh->eventtime_mysql, '2021-02-03 04:05:00', 'saved timestamp persists' );
    is( $fresh->prop('opt_backdated'), 1, 'backdated on persists' );
    $res = $cb->( GET $path );
    ($form) = grep { ( ( $_->attr('id') || '' ) eq 'js-post-entry' ) }
        HTML::Form->parse( $res->content, 'http://localhost' . $path );
    ok( $form->value('entrytime_outoforder'), 'backdated on reload is selected' );
    like( $res->content, qr/value=["']2021-02-03["']/, 'fresh reload retains date' );
    like( $res->content, qr/value=["']04:05["']/,      'fresh reload retains time' );
    $form->value( 'entrytime_outoforder', '' );
    $request = $form->click;
    $request->uri( 'http://localhost' . $path );
    $res = $cb->($request);
    is( $res->code, 200, 'backdated off save succeeds' );
    LJ::Entry::reset_singletons();
    $fresh = LJ::Entry->new( $u, ditemid => $ditemid );
    is( $fresh->prop('opt_backdated') || 0, 0, 'backdated off persists' );
    $res = $cb->( GET $path );
    ($form) = grep { ( ( $_->attr('id') || '' ) eq 'js-post-entry' ) }
        HTML::Form->parse( $res->content, 'http://localhost' . $path );
    ok( !$form->value('entrytime_outoforder'), 'backdated off reload is unselected' );
    $form->value( 'entrytime_date', 'not-a-date' );
    $form->value( 'entrytime_time', 'not-a-time' );
    $request = $form->click;
    $request->uri( 'http://localhost' . $path );
    $res = $cb->($request);
    is( $res->code, 200, 'invalid timestamp re-renders form' );
    like( $res->content, qr/not-a-date/, 'invalid date is retained' );
    like( $res->content, qr/not-a-time/, 'invalid time is retained' );
    LJ::Entry::reset_singletons();
    $fresh = LJ::Entry->new( $u, ditemid => $ditemid );
    is( $fresh->eventtime_mysql, '2021-02-03 04:05:00',
        'invalid timestamp leaves entry unchanged' );
};
done_testing;
