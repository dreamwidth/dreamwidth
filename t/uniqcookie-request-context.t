#!/usr/bin/perl
#
# t/uniqcookie-request-context.t
#
# Native request-note coverage for LJ::UniqCookie.
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
subtest 'current uniq does not leak between requests' => sub {
    request( '/a', 'A' );
    is( LJ::UniqCookie->current_uniq, 'A', 'first request reads its own native uniq note' );
    request( '/b', 'B' );
    is( LJ::UniqCookie->current_uniq, 'B', 'second request does not inherit the first uniq note' );
};
done_testing;
