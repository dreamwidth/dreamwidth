#!/usr/bin/perl
#
# This code was forked from the LiveJournal project owned and operated
# by Live Journal, Inc. The code has been modified and expanded by
# Dreamwidth Studios, LLC. These files were originally licensed under
# the terms of the license supplied by Live Journal, Inc, which can
# currently be found at:
#
# http://code.livejournal.org/trac/livejournal/browser/trunk/LICENSE-LiveJournal.txt
#
# In accordance with the original license, this code and all its
# modifications are provided under the GNU General Public License.
# A copy of that license can be found in the LICENSE file included as
# part of this distribution.

use strict;

BEGIN {
    $PaletteModify::HAVE_CRC = eval "use String::CRC32 (); 1;";
}

package PaletteModify;

sub common_alter {
    my ( $palref, $table ) = @_;
    my $length = length $table;

    my $pal_size = $length / 3;

    # tinting image?  if so, we're remaking the whole palette
    if ( my $tint = $palref->{'tint'} ) {
        my $dark = $palref->{'tint_dark'};
        my $diff = [ map { $tint->[$_] - $dark->[$_] } ( 0 .. 2 ) ];
        $palref = {};
        for ( my $idx = 0 ; $idx < $pal_size ; $idx++ ) {
            for my $c ( 0 .. 2 ) {
                my $curr = ord( substr( $table, $idx * 3 + $c ) );
                my $p    = \$palref->{$idx}->[$c];
                $$p = int( $dark->[$c] + $diff->[$c] * $curr / 255 );
            }
        }
    }

    while ( my ( $idx, $c ) = each %$palref ) {
        next if $idx >= $pal_size;
        substr( $table, $idx * 3 + $_, 1 ) = chr( $c->[$_] ) for ( 0 .. 2 );
    }

    return $table;
}

sub new_gif_palette {
    my ( $fh, $palref ) = @_;
    my $header;

    # 13 bytes for magic + image info (size, color depth, etc)
    # and then the global palette table (3*256)
    read( $fh, $header, 13 + 3 * 256 );

    # figure out how big global color table is (don't want to overwrite it)
    my $pf  = ord substr( $header, 10, 1 );
    my $gct = 2**( ( $pf & 7 ) + 1 );         # last 3 bits of packaged fields

    substr( $header, 13, 3 * $gct ) = common_alter( $palref, substr( $header, 13, 3 * $gct ) );
    return $header;
}

sub new_png_palette {
    my ( $fh, $palref ) = @_;

    # without this module, we can't proceed.
    return undef unless $PaletteModify::HAVE_CRC;

    my $imgdata;

    # Validate PNG signature
    my $png_sig = pack( "H16", "89504E470D0A1A0A" );
    my $sig;
    read( $fh, $sig, 8 );
    return undef unless $sig eq $png_sig;
    $imgdata .= $sig;

    # Start reading in chunks
    my ( $length, $type ) = ( 0, '' );
    while ( read( $fh, $length, 4 ) ) {

        $imgdata .= $length;
        $length = unpack( "N", $length );
        return undef unless read( $fh, $type, 4 ) == 4;
        $imgdata .= $type;

        if ( $type eq 'IHDR' ) {
            my $header;
            read( $fh, $header, $length + 4 );
            my ( $width, $height, $depth, $color, $compression, $filter, $interlace, $CRC ) =
                unpack( "NNCCCCCN", $header );
            return undef unless $color == 3;    # unpaletted image
            $imgdata .= $header;
        }
        elsif ( $type eq 'PLTE' ) {

            # Finally, we can go to work
            my $palettedata;
            read( $fh, $palettedata, $length );
            $palettedata = common_alter( $palref, $palettedata );
            $imgdata .= $palettedata;

            # Skip old CRC
            my $skip;
            read( $fh, $skip, 4 );

            # Generate new CRC
            my $crc = String::CRC32::crc32( $type . $palettedata );
            $crc = pack( "N", $crc );

            $imgdata .= $crc;
            return $imgdata;
        }
        else {
            my $skip;

            # Skip rest of chunk and add to imgdata
            # Number of bytes is +4 becauses of CRC
            #
            for ( my $count = 0 ; $count < $length + 4 ; $count++ ) {
                read( $fh, $skip, 1 );
                $imgdata .= $skip;
            }
        }
    }

    return undef;
}

1;
