#!/usr/bin/perl
#
# t/auth-feed.t
#
# Regression tests for feed authentication ordering and rendering.
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
use LJ::Test qw(temp_user);
use DW::Controller::Journal;
use DW::API::Key;
use MIME::Base64 qw(encode_base64);

{

    package FeedAuthRequest;
    sub get_args       { { auth => 'digest' } }
    sub header_in      { $_[1] eq 'Authorization' ? $_[0]->{authorization} : undef }
    sub header_out     { $_[0]->{headers}{ $_[1] } = $_[2] }
    sub header_out_add { shift->header_out(@_) }
    sub status         { $_[0]->{status} = $_[1] }
    sub print          { $_[0]->{body} .= $_[1] }
    sub OK             { 0 }
    sub note           { undef }
    sub content_type   { }
    sub method         { 'GET' }
    sub get_remote_ip  { '127.0.0.1' }
    sub cookie         { undef }
    sub query_string   { 'auth=digest' }
    sub uri            { '/data/rss' }
}
my $r = bless {}, 'FeedAuthRequest';
my $u = temp_user();
$u->set_password('feed-password');
my $key = DW::API::Key->new_for_user($u);
my ( $remote, $hook_remote, $render_remote );
my ( $hook_calls, $render_calls, $captcha_calls ) = ( 0, 0, 0 );
my $hooked;
no warnings 'redefine';
local *DW::Request::get                        = sub { $r };
local *LJ::get_remote                          = sub { $remote };
local *LJ::set_remote                          = sub { $remote = $_[0] };
local *DW::Routing::call                       = sub { undef };
local *DW::Controller::Journal::determine_view = sub { { mode => 'data', pathextra => '/rss' } };
local *LJ::Hooks::run_hook = sub {
    return unless $_[0] eq 'data_handler:rss';
    ++$hook_calls;
    return unless $hooked;
    return sub { $hook_remote = LJ::get_remote(); $r->print('hooked feed') };
};
local *LJ::Hooks::run_hooks  = sub { };
local *LJ::make_journal      = sub { ++$render_calls; $render_remote = $_[2]; return 'main feed' };
local *LJ::PageStats::render = sub { '' };

# If authentication happens too late this matcher would redirect to CAPTCHA.
local $LJ::CAPTCHA_HCAPTCHA_SITEKEY = 'test-sitekey';
local $LJ::SHOULD_CAPTCHA_REQUEST   = sub { ++$captcha_calls; 1 };
local $LJ::CAPTCHA_BYPASS_REGEX     = undef;
local $LJ::CAPTCHA_BYPASS_IP        = undef;

for my $use_hook ( 0, 1 ) {
    $hooked = $use_hook;
    for my $credential ( 'feed-password', $key->hash ) {
        $remote = undef;
        ( $hook_calls, $render_calls, $captcha_calls ) = ( 0, 0, 0 );
        %$r = ( authorization => 'Basic ' . encode_base64( $u->user . ':' . $credential, '' ) );
        DW::Controller::Journal->render(
            user => $u->user,
            uri  => '/data/rss',
            args => 'auth=digest'
        );
        if ( $credential eq 'feed-password' ) {
            is( $r->{status}, 401, 'Feed rejects password before rendering' );
            is( $hook_calls + $render_calls + $captcha_calls,
                0, 'Rejected credentials reach neither renderer nor CAPTCHA' );
        }
        else {
            is(
                $r->{body},
                $hooked ? 'hooked feed' : 'main feed',
                'API key reaches selected feed renderer'
            );
            my $viewer = $hooked ? $hook_remote : $render_remote;
            ok( $viewer && $viewer->equals($u), 'Renderer sees authenticated API user' );
            is( $captcha_calls, 0, 'Authenticated feed bypasses CAPTCHA request matcher' );
            is(
                $r->{headers}{'Cache-Control'},
                'private, no-store',
                'Authenticated feed remains uncacheable'
            );
        }
    }
}
$key->delete($u);
done_testing();
