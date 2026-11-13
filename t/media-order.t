# t/media-order.t
#
# Test upload-date ordering of active media.
#
# Authors:
#      SAPHID <saphid@users.noreply.github.com>
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
use DW::Media;

my $owner = temp_user();
my $other = temp_user();
my @uploaded;

END {
    $_->delete for grep { $_ && $_->is_active } @uploaded;
}

sub upload_at {
    my ( $user, $time ) = @_;
    my $media = DW::Media->upload_media(
        user => $user,
        file => 'htdocs/img/videoplaceholder.png',
    );
    die 'Failed to upload test image' unless $media;
    push @uploaded, $media;
    $user->do( 'UPDATE media SET logtime = ? WHERE userid = ? AND mediaid = ?',
        undef, $time, $user->id, $media->id );
    die 'Failed to set test upload time' if $user->err;
    return $media->id;
}

my @ids = map { upload_at( $owner, $_ ) } ( 100, (200) x 20, 300 );
my $deleted = upload_at( $owner, 400 );
$uploaded[-1]->delete;
upload_at( $other, 500 );

my @newest = reverse @ids;
my @oldest = @ids;

for my $case (
    [ 'default', {}, \@newest ],
    [ 'newest first', { oldest_first => 0 }, \@newest ],
    [ 'oldest first', { oldest_first => 1 }, \@oldest ],
) {
    my ( $name, $opts, $expected ) = @$case;
    my @media = DW::Media->get_active_for_user( $owner, %$opts, width => 200, height => 200 );
    is_deeply( [ map { $_->id } @media ], $expected,
        "$name orders by upload date and ID, excluding deleted and other-owner images" );
    is_deeply( [ map { $_->id } @media[0..19] ], [ @$expected[0..19] ],
        "$name has a stable first page across equal upload times" );
    is_deeply( [ map { $_->id } @media[20..21] ], [ @$expected[20..21] ],
        "$name keeps the remaining images on the second page" );
    my @again = DW::Media->get_active_for_user( $owner, %$opts );
    is_deeply( [ map { $_->id } @again ], $expected,
        "$name is repeatable without thumbnail options" );
}

done_testing();
