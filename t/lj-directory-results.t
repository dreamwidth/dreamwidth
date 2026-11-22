#!/usr/bin/perl
#
# t/lj-directory-results.t
#
# Test directory search results and set handle serialization.
#
# Authors:
#     Alex <saphid@users.noreply.github.com>
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
use lib "$ENV{LJHOME}/cgi-bin";
use LJ::Directory::Results;
use LJ::Directory::SetHandle;
use LJ::Directory::SetHandle::Inline;

subtest 'empty search results' => sub {
    my $results = LJ::Directory::Results->empty_set;
    is( $results->pages, 0, 'no pagination for an empty search' );
    is_deeply( [ $results->userids ], [], 'no matching users' );
    is( $results->as_string, '',     'empty results serialize without a delimiter' );
    is( $results->format,    'pics', 'picture format is the default' );
};

subtest 'result order and format' => sub {
    my $results =
        LJ::Directory::Results->new( pages => 3, userids => [ 42, 7, 18 ], format => 'simple' );
    is( $results->pages, 3, 'reports the supplied page count' );
    is_deeply( [ $results->userids ], [ 42, 7, 18 ], 'retains search order' );
    is( $results->as_string, '42,7,18', 'serializes IDs in search order' );
    is( $results->format,    'simple',  'accepts the simple format' );
    is(
        LJ::Directory::Results->new( format => 'simple-pics' )->format,
        'pics',
        'unsupported formats fall back to pictures'
    );
};

subtest 'inline handle round trip and packed data' => sub {
    my @userids = ( 16909060, 7, 4275878552 );
    my $wire    = 'Inline:16909060,7,4275878552';
    my $encoded = LJ::Directory::SetHandle::Inline->new(@userids)->as_string;
    is( $encoded, $wire, 'uses the inline wire format' );

    my $handle = LJ::Directory::SetHandle->new_from_string($wire);
    isa_ok( $handle, 'LJ::Directory::SetHandle::Inline' );
    is( $handle->as_string, $wire, 'decoding and encoding preserves the handle' );
    is( $handle->set_size,  3,     'counts IDs rather than bytes' );
    is( $handle->pack_size, 12,    'reports four packed bytes per ID' );

    my @loaded;
    $handle->load_matching_uids( sub { push @loaded, @_ } );
    is_deeply( \@loaded, \@userids, 'passes IDs to the callback in serialized order' );

    my $packed = '';
    $handle->load_pack_data( sub { $packed .= $_[0] } );
    is(
        $packed,
        "\x01\x02\x03\x04\x00\x00\x00\x07\xfe\xdc\xba\x98",
        'streams unsigned 32-bit IDs in network byte order'
    );
};

subtest 'empty and invalid handles' => sub {
    my $empty = LJ::Directory::SetHandle->new_from_string('Inline:');
    is( $empty->as_string, 'Inline:', 'empty set survives a wire round trip' );
    is( $empty->set_size,  0,         'does not decode an empty ID' );
    is( $empty->pack_size, 0,         'does not count any packed bytes' );

    my $stored = LJ::Directory::SetHandle->new_from_string('Mogile:directory-results');
    isa_ok( $stored, 'LJ::Directory::SetHandle::Mogile' );
    is( $stored->as_string, 'Mogile:directory-results', 'preserves an external handle token' );

    eval { LJ::Directory::SetHandle->new_from_string('Unknown:7') };
    like( $@, qr/Unknown set handle/, 'rejects an unrecognized handle type' );

    eval { LJ::Directory::SetHandle::Inline->new_from_string('7,18') };
    ok( $@, 'the inline parser rejects input without its type prefix' );
};

ok( !( grep { m{(?:^|/)ljlib\.pl\z} } ( keys %INC, values %INC ) ),
    'running these tests does not load ljlib.pl' );

done_testing;
