# t/userpic-factory-orientation.t
#
# Test orientation in icon factory previews and crops.
#
# Authors:
#      Dreamwidth contributors
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

use DW::BlobStore;
use Image::ExifTool;
use Image::Magick;
use LJ::Userpic;

my $image = Image::Magick->new( size => '400x240' );
my $error = $image->Read('xc:red');
die $error if $error;
for my $quadrant ( [ '200,0 399,119', 'lime' ], [ '0,120 199,239', 'blue' ],
    [ '200,120 399,239', 'white' ], )
{
    $error =
        $image->Draw( primitive => 'rectangle', points => $quadrant->[0], fill => $quadrant->[1] );
    die $error if $error;
}
$image->Set( magick => 'JPEG', quality => 95 );
my $jpeg = $image->ImageToBlob;

sub check_pixels {
    my ( $result, $dimensions, $corner, $label ) = @_;
    ok( $result, "$label produced an image" ) or return;
    is( $result->[1], 'image/jpeg', "$label is JPEG" );
    is_deeply( [ @$result[ 2, 3 ] ], $dimensions, "$label has the expected dimensions" );

    my $decoded = Image::Magick->new;
    my $error   = $decoded->BlobToImage( ${ $result->[0] } );
    is( "$error", '', "$label can be decoded" ) or return;
    my @rgb = $decoded->GetPixel( x => int( $result->[2] / 4 ), y => int( $result->[3] / 4 ) );
    is_deeply( [ map { $_ > 0.5 ? 1 : 0 } @rgb[ 0 .. 2 ] ],
        $corner, "$label shows the expected quadrant" );

    my $info = Image::ExifTool::ImageInfo( $result->[0], 'IFD0:Orientation', { PrintConv => 0 } );
    is( $info->{Orientation} // 1, 1, "$label does not tell the browser to reorient it" );
}

my $red   = [ 1, 0, 0 ];
my $green = [ 0, 1, 0 ];
my $blue  = [ 0, 0, 1 ];
my $white = [ 1, 1, 1 ];

for my $case (
    [ undef, 'no metadata',       [ 200, 120 ], $red,   $green ],
    [ 1,     'upright',           [ 200, 120 ], $red,   $green ],
    [ 2,     'mirrored',          [ 200, 120 ], $green, $red ],
    [ 3,     'rotated 180',       [ 200, 120 ], $white, $blue ],
    [ 4,     'flipped',           [ 200, 120 ], $blue,  $white ],
    [ 5,     'transposed',        [ 120, 200 ], $red,   $blue ],
    [ 6,     'rotated clockwise', [ 120, 200 ], $blue,  $red ],
    [ 7,     'transverse',        [ 120, 200 ], $white, $green ],
    [ 8,     'rotated CCW',       [ 120, 200 ], $green, $white ],
    )
{
    my ( $orientation, $label, $dimensions, $top_left, $top_right ) = @$case;
    subtest $label => sub {
        my $data;
        if ( defined $orientation ) {
            my $exif = Image::ExifTool->new;
            $exif->SetNewValue( 'IFD0:Orientation' => $orientation, Type => 'Raw' );
            is( $exif->WriteInfo( \$jpeg, \$data ), 1, 'wrote synthetic EXIF orientation' )
                or BAIL_OUT('Could not create EXIF fixture');
            my $info = Image::ExifTool::ImageInfo( \$data, 'IFD0:Orientation', { PrintConv => 0 } );
            is( $info->{Orientation}, $orientation, 'fixture has the expected EXIF orientation' )
                or BAIL_OUT('Could not read EXIF fixture');
        }
        else {
            $data = $jpeg;
        }

        my $key = 'factory-orientation';
        ok( DW::BlobStore->store( temp => $key, \$data ), 'stored the upload' )
            or BAIL_OUT('Could not store EXIF fixture');

        my $preview = LJ::Userpic->get_upf_scaled( mogkey => $key, size => 200 );
        check_pixels( $preview, $dimensions, $top_left, 'preview' );

        my $left = $dimensions->[0] / 2;
        my $crop = LJ::Userpic->get_upf_scaled(
            mogkey => $key,
            size   => 200,
            x1     => $left,
            y1     => 0,
            x2     => $left + 55,
            y2     => 55,
        );
        check_pixels( $crop, [ 100, 100 ], $top_right, 'upper-right crop' );

        DW::BlobStore->delete( temp => $key );
    };
}

ok( !LJ::Userpic->get_upf_scaled( mogkey => 'missing-factory-orientation' ),
    'missing upload fails' );

done_testing();
