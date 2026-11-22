#!/usr/bin/perl
#
# Standalone tests for DW::StatData and DW::RPC
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.

use strict;
use warnings;

use lib "$ENV{LJHOME}/extlib/lib/perl5", "$ENV{LJHOME}/cgi-bin";
use JSON::PP;
use Test::More;

use DW::Request;
use DW::RPC;
use DW::StatData;
use HTTP::Request;

subtest 'StatData groups snapshots by elapsed days' => sub {
    my $now   = time;
    my $day   = 24 * 60 * 60;
    my %older = (
        $now - 2 * $day - $day / 2  => { active => 17 },
        $now - 10 * $day - $day / 2 => { active => 31 },
    );
    my $rows = DW::StatData->load( { %older, $now - $day / 2 => { active => 0 } } );

    is_deeply( [ sort { $a <=> $b } keys %$rows ], [ 0, 2, 10 ], 'uses whole elapsed days' );
    isa_ok( $rows->{0}, 'DW::StatData' );
    is( $rows->{0}->value('active'),  0,     'preserves a zero count' );
    is( $rows->{0}->value('missing'), undef, 'an absent statistic has no value' );
    is_deeply( $rows->{2}->data,  { active => 17 }, 'keeps the two-day snapshot' );
    is_deeply( $rows->{10}->data, { active => 31 }, 'keeps the ten-day snapshot' );
    is( DW::StatData->load_latest( \%older )->value('active'),
        17, 'selects the newest numerically' );
    is( DW::StatData->load_latest( {} ), undef, 'no snapshots means no latest value' );
};

my $json = JSON::PP->new->utf8->canonical;

subtest 'RPC writes JSON and returns request success' => sub {
    my $payload = { rows => [ { count => 0, label => "quote\" and newline\n" } ] };
    check_rpc_response( 'out', $payload, %$payload );
    check_rpc_response( 'out', {} );
    check_rpc_response( 'err', { error => 'Invalid input' }, 'Invalid input' );
    check_rpc_response( 'err',   { error => '' } );
    check_rpc_response( 'err',   { error => '' }, 0 );
    check_rpc_response( 'alert', { alert => 'Cannot save', error => 1 }, 'Cannot save' );
};

ok( !( grep { defined && m{(?:^|/)ljlib\.pl\z} } keys %INC, values %INC ),
    'does not load ljlib.pl' );

done_testing;

sub check_rpc_response {
    my ( $method, $expected, @args ) = @_;
    DW::Request->reset;
    my $request = DW::Request::Standard->new( HTTP::Request->new( POST => 'http://example.com/' ) );

    is( DW::RPC->$method(@args), $request->OK, "$method returns request success" );
    is(
        $json->encode( $json->decode( $request->response_content ) ),
        $json->encode($expected),
        "$method writes the expected JSON object"
    );
}
