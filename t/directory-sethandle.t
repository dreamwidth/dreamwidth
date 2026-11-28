# t/directory-sethandle.t
#
# Test inline and stored directory result handles without loading ljlib.pl.
#
# Authors:
#      Alex (SAPHID) <saphid@users.noreply.github.com>
#
# Copyright (c) 2026 by Dreamwidth Studios, LLC.
#
# This program is free software; you may redistribute it and/or modify it under
# the same terms as Perl itself.  For a copy of the license, please reference
# 'perldoc perlartistic' or 'perldoc perlgpl'.
#

use strict;
use warnings;
use lib "$ENV{LJHOME}/extlib/lib/perl5", "$ENV{LJHOME}/cgi-bin";

use Test::More;
use Log::Log4perl;
use LJ::Directory::SetHandle;
use DW::BlobStore;

subtest 'inline handles preserve order and use network byte order' => sub {
    my $wire   = 'Inline:16909060,42,42,4294967295';
    my $handle = LJ::Directory::SetHandle->new_from_string($wire);
    isa_ok( $handle, 'LJ::Directory::SetHandle::Inline' );
    is( $handle->as_string, $wire, 'round trips the inline handle' );
    is( $handle->set_size,  4,     'counts every UID, including repeats' );
    is( $handle->pack_size, 16,    'each UID occupies four bytes' );

    my @batches;
    $handle->load_matching_uids( sub { push @batches, [@_] } );
    is_deeply( \@batches, [ [ 16909060, 42, 42, 4294967295 ] ], 'returns one ordered UID batch' );

    my @packed;
    $handle->load_pack_data( sub { push @packed, unpack( 'H*', $_[0] ) } );
    is_deeply( \@packed, ['010203040000002a0000002affffffff'], 'packs unsigned big-endian UIDs' );
};

subtest 'empty and invalid handles' => sub {
    my $empty = LJ::Directory::SetHandle->new_from_string('Inline:');
    is( $empty->as_string, 'Inline:', 'round trips an empty inline handle' );
    is( $empty->set_size,  0,         'an empty handle has no UIDs' );
    is( $empty->pack_size, 0,         'an empty handle advertises zero bytes' );

    my @packed;
    $empty->load_pack_data( sub { push @packed, [@_] } );
    is_deeply( \@packed, [ [''] ], 'delivers a single empty payload' );

    eval { LJ::Directory::SetHandle->new_from_string('Other:42') };
    like( $@, qr/Unknown set handle/, 'rejects an unrecognized handle prefix' );
    ok( !eval { LJ::Directory::SetHandle::Inline->new_from_string('Mogile:key'); 1 },
        'the inline parser rejects a Mogile handle' );
    ok( !eval { LJ::Directory::SetHandle::Mogile->new_from_string('Inline:42'); 1 },
        'the Mogile parser rejects an inline handle' );
};

subtest 'Mogile handles read stored results and report missing data' => sub {
    my $wire = 'Mogile:fixture:results';

    # Select BlobStore's real temporary LocalDisk backend without the ljlib.pl bootstrap.
    local *LJ::in_test = sub { 1 };
    Log::Log4perl->easy_init($Log::Log4perl::OFF);

    my @packed;
    my $collect = sub { push @packed, [@_] };
    my $missing = LJ::Directory::SetHandle->new_from_string($wire);
    eval { $missing->load_pack_data($collect) };
    like( $@, qr/Failed to load search results/, 'missing results fail before delivery' );
    is_deeply( \@packed, [], 'does not invoke the callback on a failed read' );

    my $payload = pack( 'H*', '010203040000002affffffff' );
    my $key     = 'dsh:fixture:results';
    ok( DW::BlobStore->store( directorysearch => $key, \$payload ),
        'stores binary search results' );
    my $handle = LJ::Directory::SetHandle->new_from_string($wire);
    isa_ok( $handle, 'LJ::Directory::SetHandle::Mogile' );
    is( $handle->as_string, $wire, 'round trips a storage key containing a colon' );
    is( $handle->pack_size, 12,    'reports the stored payload size in bytes' );
    $handle->load_pack_data($collect);
    is_deeply( \@packed, [ [$payload] ], 'delivers the exact stored bytes' );

    ok( DW::BlobStore->delete( directorysearch => $key ), 'removes the stored fixture' );
    @packed = ();
    $handle->load_pack_data($collect);
    is_deeply( \@packed, [ [$payload] ], 'a loaded handle retains its payload' );

    my $fresh = LJ::Directory::SetHandle->new_from_string($wire);
    eval { $fresh->pack_size };
    like( $@, qr/Failed to load search results/, 'a fresh handle cannot size a missing payload' );
};

ok( !( grep { defined && m{(?:^|/)ljlib[.]pl\z} } keys %INC, values %INC ),
    'ljlib.pl was not loaded in this process' );

done_testing;
