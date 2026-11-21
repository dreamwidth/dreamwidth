# t/media-security-normalization.t
#
# Media security normalization must preserve access on upload and update.
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

my $owner        = temp_user();
my $trusted      = temp_user();
my $group_viewer = temp_user();
my $outsider     = temp_user();
$owner->add_edge( $_, trust => { nonotify => 1 } ) for ( $trusted, $group_viewer );
my $group = $owner->create_trust_group( groupname => 'normalization' );
$owner->edit_trustmask( $group_viewer, add => $group );
my $group_mask = 1 << $group;

my @objects;
END { $_->delete for @objects; }

sub check_item {
    my ( $item, $security, $mask, $visible ) = @_;
    is( $item->security,  $security, 'stored security' );
    is( $item->allowmask, $mask,     'stored mask' );
    is( $item->visible_to($owner)        ? 1 : 0, 1,             'owner retains access' );
    is( $item->visible_to($trusted)      ? 1 : 0, $visible->[0], 'trusted viewer access' );
    is( $item->visible_to($group_viewer) ? 1 : 0, $visible->[1], 'group member access' );
    is( $item->visible_to($outsider)     ? 1 : 0, $visible->[2], 'outsider access' );
}

my $mutable = DW::Media->upload_media(
    user     => $owner,
    file     => 'htdocs/img/videoplaceholder.png',
    security => 'private'
);
push @objects, $mutable;

for my $case (
    [ 'public', 0, 'public', 0, [ 1, 1, 1 ] ],
    [ 'public', $group_mask, 'public', 0, [ 1, 1, 1 ] ],
    [ 'private', 0, 'private', 0, [ 0, 0, 0 ] ],
    [ 'private', $group_mask, 'private', 0, [ 0, 0, 0 ] ],
    [ 'usemask', undef, 'usemask', 0, [ 0, 0, 0 ] ],
    [ 'usemask', 0,     'usemask', 0, [ 0, 0, 0 ] ],
    [ 'usemask', 1,     'usemask', 1, [ 1, 1, 0 ] ],
    [ 'usemask', $group_mask, 'usemask', $group_mask, [ 0, 1, 0 ] ],
    [ 'friends', undef, 'usemask', 1, [ 1, 1, 0 ] ],
    [ 'friends', 0,     'usemask', 1, [ 1, 1, 0 ] ],
    [ 'friends', $group_mask, 'usemask', 1, [ 1, 1, 0 ] ],
    [ 'access', undef, 'usemask', 1, [ 1, 1, 0 ] ],
    [ 'access', 0,     'usemask', 1, [ 1, 1, 0 ] ],
    [ 'access', $group_mask, 'usemask', 1, [ 1, 1, 0 ] ],
    )
{
    my ( $input, $mask, $security, $expected_mask, $visible ) = @$case;
    my $name = "$input mask " . ( defined $mask ? $mask : 'undefined' );
    subtest "upload $name" => sub {
        my $item = DW::Media->upload_media(
            user      => $owner,
            file      => 'htdocs/img/videoplaceholder.png',
            security  => $input,
            allowmask => $mask,
        );
        push @objects, $item;
        check_item( $item, $security, $expected_mask, $visible );
    };
    subtest "update $name" => sub {
        ok( $mutable->set_security( security => $input, allowmask => $mask ), 'security updated' );
        check_item( $mutable, $security, $expected_mask, $visible );
    };
}

subtest 'caller defaults and invalid values' => sub {
    my $default = DW::Media->upload_media(
        user => $owner,
        file => 'htdocs/img/videoplaceholder.png',
    );
    push @objects, $default;
    check_item( $default, 'public', 0, [ 1, 1, 1 ] );

    eval { $mutable->set_security() };
    like( $@, qr/Invalid argument hash passed to set_security/, 'update still needs security' );
    eval { $mutable->set_security( security => 'unknown' ) };
    like( $@, qr/Invalid security type passed to set_security/, 'invalid update is rejected' );
    eval {
        DW::Media->upload_media(
            user     => $owner,
            file     => 'htdocs/img/videoplaceholder.png',
            security => 'unknown'
        );
    };
    like( $@, qr/Invalid security for uploaded file/, 'invalid upload is rejected' );
    check_item( $mutable, 'usemask', 1, [ 1, 1, 0 ] );
};

done_testing;
