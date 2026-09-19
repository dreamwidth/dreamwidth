#!/usr/bin/perl
#
# t/auth-importer.t
#
# Regression tests for importer API-key authentication and comment exports.
#
# Authors:
#     Mark Smith <mark@dreamwidth.org>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself. For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use LJ::Test qw(temp_user temp_comm);
use DW::Auth::Challenge;
use DW::Auth::TOTP;
use DW::API::Key;
use DW::Controller::Export;
use DW::Worker::ContentImporter::LiveJournal;
use DW::Worker::ContentImporter::LiveJournal::Comments;
use Digest::MD5 qw(md5_hex);
use HTTP::Response;
use URI;

{

    package ImportAuthRequest;
    sub get_args  { $_[0]->{get}  || {} }
    sub post_args { $_[0]->{post} || {} }
    sub did_post  { 1 }
    sub header_in { '' }
    sub header_out { $_[0]->{headers}{ $_[1] } = $_[2] }
    sub status { $_[0]->{status} = $_[1] }
    sub print         { $_[0]->{body} .= $_[1] }
    sub content_type  { }
    sub note          { undef }
    sub get_remote_ip { '127.0.0.1' }
    sub OK            { 0 }
}
my $r      = bless {}, 'ImportAuthRequest';
my $source = temp_user();
$source->set_password('source-password');
DW::Auth::TOTP->enable( $source, DW::Auth::TOTP->generate_secret );
my $key   = DW::API::Key->new_for_user($source);
my $other = temp_user();
no warnings 'redefine';
local *DW::Request::get    = sub { $r };
local *LJ::get_remote      = sub { $other };
local *LJ::set_remote      = sub { die 'API export must not change browser identity' };
local *LJ::Session::create = sub { die 'API export must not create browser sessions' };
my @methods;
my $worker = 'DW::Worker::ContentImporter::LiveJournal';
local *DW::Worker::ContentImporter::LiveJournal::xmlrpc_call_helper = sub {
    my ( $class, $opts, $client, $method, $args ) = @_;
    push @methods, $method;
    return { challenge => DW::Auth::Challenge->generate } if $method eq 'LJ.XMLRPC.getchallenge';
    my ( $error, %flags );
    ok(
        LJ::Protocol::authenticate( $args, \$error, \%flags ),
        'Importer XML-RPC uses a valid API-key challenge'
    );
    return { result => 'ok' };
};
my $data = {
    hostname     => 'dreamwidth.org',
    username     => $source->user,
    password_md5 => md5_hex( $key->hash ),
    userid       => $other->id
};
my $result = $worker->call_xmlrpc( $data, 'login', {} );
is( $result->{result}, 'ok', 'Importer XML-RPC remains compatible with API keys' );
for my $credential ( 'source-password', $key->hash ) {
    %$r = (
        post   => $worker->challenge_auth( { %$data, password_md5 => md5_hex($credential) } ),
        get    => { get => 'comment_meta' },
        status => 200
    );
    DW::Controller::Export::comment_handler();
    if ( $credential eq 'source-password' ) {
        is( $r->{status}, 401, 'Comment export rejects source password' );
        unlike( $r->{body}, qr/<livejournal>/, 'Password cannot export comments' );
    }
    else {
        is( $r->{status}, 200, 'Comment export accepts API key for MFA account' );
        like( $r->{body}, qr/<livejournal>/, 'API key exports comment XML' );
        is(
            $r->{headers}{'Cache-Control'},
            'private, no-store',
            'Authenticated export is not cacheable'
        );
    }
}
for my $target ( $other, temp_comm() ) {
    %$r = (
        post   => $worker->challenge_auth($data),
        get    => { authas => $target->user },
        status => 200
    );
    my ($ok) = DW::Controller::Export::_comment_auth();
    ok( !$ok, 'API key cannot export an unrelated journal' );
    is( $r->{status}, 403, 'Unmanaged authas journal is forbidden' );
}
my $community = temp_comm();
LJ::set_rel( $community, $source, 'A' );
%$r = ( post => $worker->challenge_auth($data), get => { authas => $community->user } );
my ( $ok, $rv ) = DW::Controller::Export::_comment_auth();
ok( $ok && $rv->{u}->equals($community), 'Community administrator API key can export community' );

# Exercise the worker's actual request construction without network access.
{
    my $request;
    local *LWP::UserAgent::request = sub {
        $request = $_[1];
        return HTTP::Response->new( 401, 'Test response' );
    };
    local *DW::Worker::ContentImporter::LiveJournal::Comments::get_lj_session =
        sub { die 'Dreamwidth comment import must not request a browser session' };
    local *DW::Worker::ContentImporter::LiveJournal::Comments::challenge_auth =
        sub { $worker->challenge_auth( $_[1] ) };
    DW::Worker::ContentImporter::LiveJournal::Comments->do_authed_comment_fetch( $data,
        'comment_meta', 0, 100, sub { } );
    is( $request->method, 'POST', 'Dreamwidth comments use authenticated export POST' );
    ok( !$request->header('Cookie'), 'API export carries no browser cookie' );
    my %auth = URI->new( 'http://localhost/?' . $request->content )->query_form;
    my ( $error, %flags );
    ok( LJ::Protocol::authenticate( \%auth, \$error, \%flags ),
        'Export POST carries valid key challenge' );
    unlike( $request->content, qr/\Q@{[$key->hash]}\E/, 'Export POST does not transmit raw key' );
}
{
    my $request;
    local *LWP::UserAgent::request = sub {
        $request = $_[1];
        return HTTP::Response->new( 401, 'Test response' );
    };
    local *DW::Worker::ContentImporter::LiveJournal::Comments::get_lj_session =
        sub { 'legacy-source-session' };
    DW::Worker::ContentImporter::LiveJournal::Comments->do_authed_comment_fetch(
        { %$data, hostname => 'livejournal.com' },
        'comment_meta', 0, 100, sub { } );
    is( $request->method, 'GET', 'Other source sites retain legacy export GET' );
    is(
        $request->header('Cookie'),
        'ljsession=legacy-source-session',
        'Other source sites retain session authentication'
    );
}
$key->delete($source);
%$r = ( post => $worker->challenge_auth($data), get => {} );
($ok) = DW::Controller::Export::_comment_auth();
ok( !$ok && $r->{status} == 401, 'Revoked API key cannot export comments' );
done_testing();
