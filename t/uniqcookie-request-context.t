#!/usr/bin/perl
# Native request-note coverage for LJ::UniqCookie.
# Copyright (c) 2026 by Dreamwidth Studios, LLC. Same terms as Perl itself.
use strict;
use warnings;
no warnings 'redefine';
use Test::More;
BEGIN { $LJ::_T_CONFIG = 1; require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use DW::Cache;
use LJ::UniqCookie;

sub request {
    my ( $path, $uniq ) = @_;
    DW::Request->reset;
    DW::Cache->request->clear;
    open my $input, '<', \( my $body = '' ) or die $!;
    my $r = DW::Request->get(
        plack_env => {
            REQUEST_METHOD    => 'GET',
            PATH_INFO         => $path,
            QUERY_STRING      => '',
            SERVER_NAME       => 'localhost',
            SERVER_PORT       => 80,
            HTTP_HOST         => 'localhost',
            'psgi.version'    => [ 1, 1 ],
            'psgi.url_scheme' => 'http',
            'psgi.input'      => $input,
            'psgi.errors'     => do { open my $fh, '>', \( my $err = '' ); $fh }
        }
    );
    $r->note( uniq => $uniq ) if defined $uniq;
    return $r;
}
subtest 'current uniq preserves override, request cache, and A/B note isolation' => sub {
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ = 'override';
    request( '/a', 'A' );
    is( LJ::UniqCookie->current_uniq, 'override', 'test override retains precedence' );
    local $LJ::_T_UNIQCOOKIE_CURRENT_UNIQ;
    request( '/a', 'A' );
    is( LJ::UniqCookie->current_uniq, 'A', 'first request reads native uniq note' );
    request( '/b', 'B' );
    is( LJ::UniqCookie->current_uniq, 'B', 'second request does not inherit first uniq note' );
    DW::Request->reset;
    DW::Cache->request->clear;
    is( LJ::UniqCookie->current_uniq, undef, 'no request retains undef fallback' );
};
subtest 'sysban URI path exception and cookie mapping remain unchanged' => sub {
    local $LJ::BLOCKED_BOT_URI               = '/blocked';
    local *LJ::UniqCookie::parts_from_cookie = sub { return ( 'uniq', 1, '' ) };
    local *LJ::sysban_check                  = sub { return $_[1] eq 'uniq' };
    request('/blocked/path');
    ok( !LJ::UniqCookie->sysban_should_block, 'blocked URI prefix bypass remains unchanged' );
    request('/other');
    ok( LJ::UniqCookie->sysban_should_block, 'other URI retains uniq sysban decision' );
    DW::Request->reset;
    ok( !LJ::UniqCookie->sysban_should_block, 'no request remains non-blocking' );
};
done_testing;
