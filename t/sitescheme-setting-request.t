#!/usr/bin/perl
# Request-local SiteScheme regression coverage for the settings hub.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
use Test::More;
use HTTP::Request::Common;
use HTML::Form;

BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::SiteScheme;
use LJ::Session;
use LJ::Test qw(temp_user);
use Plack::Test;

plan skip_all => 'SiteScheme settings integration requires a development server'
    unless $LJ::IS_DEV_SERVER;

my @schemes = map { $_->{scheme} } DW::SiteScheme->available;
my %scheme  = map { $_ => 1 } @schemes;
plan skip_all => 'configured tropo red and purple schemes are required for wrapper checks'
    unless $scheme{'tropo-red'} && $scheme{'tropo-purple'};

my $app = do "$ENV{LJHOME}/app.psgi";
die $@ unless ref $app eq 'CODE';

my $u = temp_user();
$u->update_self( { status => 'A' } );
my $session        = LJ::Session->create( $u, nolog => 1 );
my $session_cookie = join '; ',
    'ljmastersession=' . $session->master_cookie_string,
    'ljloggedin=' . $session->loggedin_cookie_string;
my $field = 'LJ__Setting__SiteScheme_sitescheme';
my $url   = '/manage/settings/?cat=display';

sub cookie_headers {
    my ($res) = @_;
    return $res->headers->header('Set-Cookie');
}

sub display_form {
    my ( $send, $cookie ) = @_;
    my $res = $send->( GET $url, Cookie => $cookie );
    is( $res->code, 200, 'display settings form renders' );
    my ($form) = grep { ( $_->attr('id') || '' ) eq 'settings_form' }
        HTML::Form->parse( $res->content, 'http://localhost' . $url );
    ok( $form,                     'actual display settings form parses' );
    ok( $form->find_input($field), 'SiteScheme choice is rendered by the actual settings form' );
    return ( $res, $form );
}

sub submit_scheme {
    my ( $send, $cookie, $value ) = @_;
    my ( undef, $form ) = display_form( $send, $cookie );
    $form->value( $field, $value );
    my $req = $form->click;
    $req->uri( 'http://localhost' . $url );
    $req->header( Cookie => $cookie );
    return $send->($req);
}

local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'sitescheme-request-context';
test_psgi $app, sub {
    my $send = shift;

    my $res = submit_scheme( $send, $session_cookie, 'tropo-purple' );
    is( $res->code, 200, 'selected non-default scheme saves through the real settings form' );
    like(
        $res->content,
        qr/<body[^>]*class="tropo tropo-purple"/,
        'same settings POST response uses the selected native request scheme wrapper'
    );
    my @set = cookie_headers($res);
    like(
        join( "\n", @set ),
        qr/\bBMLschemepref=tropo-purple\b/,
        'non-default save preserves the existing BMLschemepref cookie name and value'
    );
    my $fresh = LJ::load_userid( $u->id, 1 );
    is( $fresh->prop('schemepref'),
        'tropo-purple', 'selected scheme persists to the user property' );

    $res = $send->( GET $url, Cookie => "$session_cookie; BMLschemepref=tropo-purple" );
    is( $res->code, 200, 'fresh settings GET succeeds with the saved scheme cookie' );
    like(
        $res->content,
        qr/<body[^>]*class="tropo tropo-purple"/,
        'fresh request applies the saved scheme through normal cookie selection'
    );

    my ( undef, $form ) = display_form( $send, "$session_cookie; BMLschemepref=tropo-purple" );
    my $token = $form->value('lj_form_auth');
    $res = $send->(
        POST $url,
        Cookie  => "$session_cookie; BMLschemepref=tropo-purple",
        Content => { lj_form_auth => $token, $field => 'not-an-available-scheme' },
    );
    is( $res->code, 200, 'invalid scheme remains an in-page settings validation response' );
    like( $res->content, qr/invalid/i,
        'invalid scheme retains the existing validation error behavior' );
    $fresh = LJ::load_userid( $u->id, 1 );
    is( $fresh->prop('schemepref'),
        'tropo-purple', 'invalid scheme cannot change persisted preference' );

    $res = submit_scheme( $send, "$session_cookie; BMLschemepref=tropo-purple", 'tropo-red' );
    is( $res->code, 200, 'default scheme saves through the real settings form' );
    like(
        $res->content,
        qr/<body[^>]*class="tropo tropo-red"/,
        'same default-scheme POST response changes wrapper immediately'
    );
    @set = cookie_headers($res);
    like(
        join( "\n", @set ),
        qr/\bBMLschemepref=.*expires=/i,
        'default save retains existing BMLschemepref deletion behavior'
    );
    $fresh = LJ::load_userid( $u->id, 1 );
    is( $fresh->prop('schemepref'), 'tropo-red', 'default scheme persists to the user property' );

    $res = $send->( GET $url, Cookie => $session_cookie );
    is( $res->code, 200, 'fresh request without deleted preference cookie succeeds' );
    like(
        $res->content,
        qr/<body[^>]*class="tropo tropo-red"/,
        'fresh request falls back to the configured default wrapper after cookie deletion'
    );
};

done_testing;
