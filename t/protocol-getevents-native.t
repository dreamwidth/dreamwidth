#!/usr/bin/perl
#
# t/protocol-getevents-native.t
#
# Exercise protocol entry retrieval inside and outside a native web request.
#
# Authors:
#      Mark Smith <mark@dreamwidth.org>
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
use HTTP::Request::Common qw(GET);
use Plack::Test;
BEGIN { require "$ENV{LJHOME}/cgi-bin/ljlib.pl"; }
use DW::Request;
use DW::Request::Plack;
use LJ::Protocol;
use LJ::Test qw(temp_user);

my $u = temp_user();
$u->update_self( { status => 'A' } );
my $entry =
    $u->t_post_fake_entry( subject => 'Native retrieval', body => 'Protocol entry content' );

sub retrieve {
    my $err;
    my $res =
        LJ::Protocol::do_request( 'getevents',
        { username => $u->user, selecttype => 'lastn', howmany => 1 },
        \$err, { noauth => 1 } );
    ok( $res, 'getevents succeeds' ) or diag( $err // 'no protocol error' );
    is( $res->{events}->[0]->{subject}, 'Native retrieval', 'returns the requested entry' );
}

subtest 'without an active request' => sub {
    DW::Request->reset;
    ok( !DW::Request->get, 'no active request' );
    retrieve();
};

subtest 'with an active native request' => sub {
    test_psgi sub {
        my $env = shift;
        DW::Request->reset;
        DW::Request->get( plack_env => $env );
        retrieve();
        return [ 200, [ 'Content-Type' => 'text/plain' ], ['ok'] ];
    }, sub {
        my $res = shift->( GET 'http://localhost/protocol-test' );
        is( $res->code, 200, 'request completes' );
    };
    DW::Request->reset;
};

done_testing;
