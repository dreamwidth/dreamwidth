#!/usr/bin/perl
# Entry form rendering regressions for errors, native limits, and date labels.
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
        subject  => 'Original title',
        event    => 'Original body',
        year     => 2026,
        mon      => 9,
        day      => 22,
        hour     => 12,
        min      => 0,
        security => 'public'
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
    like(
        $res->content,
qr/name=["']current_music["'][^>]*maxlength=["']80["']|maxlength=["']80["'][^>]*name=["']current_music["']/,
        'English music field keeps 80-character native limit'
    );
    like(
        $res->content,
qr/name=["']current_location["'][^>]*maxlength=["']80["']|maxlength=["']80["'][^>]*name=["']current_location["']/,
        'English location field keeps 80-character native limit'
    );
    like(
        $res->content,
        qr/<label[^>]*for=["']js-entrytime-date["'][^>]*>\s*Date\s*<\/label>/,
        'date textbox has an accessible translated label'
    );
    like(
        $res->content,
        qr/<label[^>]*for=["']js-entrytime-time["'][^>]*>\s*Time\s*<\/label>/,
        'time textbox has an accessible translated label'
    );
    my ($form) = grep { ( ( $_->attr('id') || '' ) eq 'js-post-entry' ) }
        HTML::Form->parse( $res->content, 'http://localhost' . $path );
    ok( $form, 'actual edit form parses' ) or return;
    my @edit_posts = grep { ( $_->name || '' ) eq 'action:post' } $form->inputs;
    is( scalar @edit_posts, 2, 'both native edit submit controls retain action:post' );
    $form->value( 'subject',        'Retained invalid title' );
    $form->value( 'event',          '' );
    $form->value( 'entrytime_date', 'not-a-date' );
    $form->value( 'entrytime_time', 'not-a-time' );
    my $request = $form->click;
    $request->uri( 'http://localhost' . $path );
    $res = $cb->($request);
    is( $res->code, 200, 'invalid edit re-renders the form' );
    like(
        $res->content,
        qr/Must provide entry text/i,
        'empty-body validation renders the existing root legacy message'
    );
    my $error_count = () = $res->content =~ /Must provide entry text/ig;
    is( $error_count, 1, 'outer wrapper renders exactly one useful general error' );
    unlike(
        $res->content,
        qr/\[missing string|error\.noentry/,
        'empty-body response exposes no missing-string banner or raw key'
    );
    like( $res->content, qr/Retained invalid title/, 'invalid edit retains submitted title' );
    like(
        $res->content,
        qr/value=["']not-a-date["']|not-a-date/,
        'invalid edit retains submitted date'
    );
    LJ::Entry::reset_singletons();
    my $fresh = LJ::Entry->new( $u, ditemid => $ditemid );
    is( $fresh->subject_raw, 'Original title', 'invalid edit leaves persisted title unchanged' );
    is( $fresh->event_raw,   'Original body',  'invalid edit leaves persisted body unchanged' );
    local $LJ::DEFAULT_LANG = 'ru';
    $res = $cb->( GET $path);
    is( $res->code, 200, 'Russian-default edit form renders' );
    like(
        $res->content,
qr/name=["']current_music["'][^>]*maxlength=["']100["']|maxlength=["']100["'][^>]*name=["']current_music["']/,
        'Russian music field uses native 100-character limit'
    );
    like(
        $res->content,
qr/name=["']current_location["'][^>]*maxlength=["']100["']|maxlength=["']100["'][^>]*name=["']current_location["']/,
        'Russian location field uses native 100-character limit'
    );
};
done_testing;
