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
#

package S2::Color;
use strict;

# This is a helper package, useful for creating color lightening/darkening
# functions in core layers.
#

# rgb to hsv
# r, g, b = [0, 255]
# h, s, v = [0, 1), [0, 1], [0, 1]
sub rgb_to_hsv {
    my ( $r, $g, $b ) = map { $_ / 255 } @_;
    my ( $h, $s, $v );

    my ( $max, $min ) = ( $r, $r );
    foreach ( $g, $b ) {
        $max = $_ if $_ > $max;
        $min = $_ if $_ < $min;
    }
    return ( 0, 0, 0 ) if $max == 0;

    $v = $max;

    my $delta = $max - $min;

    $s = $delta / $max;
    return ( 0, $s, $v ) unless $delta;

    if ( $r == $max ) {
        $h = ( $g - $b ) / $delta;
    }
    elsif ( $g == $max ) {
        $h = 2 + ( $b - $r ) / $delta;
    }
    else {
        $h = 4 + ( $r - $g ) / $delta;
    }

    $h = ( $h * 60 ) % 360 / 360;

    return ( $h, $s, $v );
}

# hsv to rgb
# h, s, v = [0, 1), [0, 1], [0, 1]
# r, g, b = [0, 255], [0, 255], [0, 255]
sub hsv_to_rgb {
    my ( $H, $S, $V ) = @_;

    if ( $S == 0 ) {
        $V *= 255;
        return ( $V, $V, $V );
    }

    $H *= 6;
    my $I = POSIX::floor($H);

    my $F = $H - $I;
    my $P = $V * ( 1 - $S );
    my $Q = $V * ( 1 - $S * $F );
    my $T = $V * ( 1 - $S * ( 1 - $F ) );

    foreach ( $V, $T, $P, $Q ) {
        $_ = int( $_ * 255 + 0.5 );
    }

    return ( $V, $T, $P ) if $I == 0;
    return ( $Q, $V, $P ) if $I == 1;
    return ( $P, $V, $T ) if $I == 2;
    return ( $P, $Q, $V ) if $I == 3;
    return ( $T, $P, $V ) if $I == 4;

    return ( $V, $P, $Q );
}

# rgb to hsv
# r, g, b = [0, 255], [0, 255], [0, 255]
# returns: (h, s, l) = [0, 1), [0, 1], [0, 1]
sub rgb_to_hsl {

    # convert rgb to 0-1
    my ( $R, $G, $B ) = map { $_ / 255 } @_;

    # get min/max of {r, g, b}
    my ( $max, $min ) = ( $R, $R );
    foreach ( $G, $B ) {
        $max = $_ if $_ > $max;
        $min = $_ if $_ < $min;
    }

    # is gray?
    my $delta = $max - $min;
    if ( $delta == 0 ) {
        return ( 0, 0, $max );
    }

    my ( $H, $S );
    my $L = ( $max + $min ) / 2;

    if ( $L < 0.5 ) {
        $S = $delta / ( $max + $min );
    }
    else {
        $S = $delta / ( 2.0 - $max - $min );
    }

    if ( $R == $max ) {
        $H = ( $G - $B ) / $delta;
    }
    elsif ( $G == $max ) {
        $H = 2 + ( $B - $R ) / $delta;
    }
    elsif ( $B == $max ) {
        $H = 4 + ( $R - $G ) / $delta;
    }

    $H *= 60;
    $H += 360.0 if $H < 0.0;
    $H -= 360.0 if $H >= 360.0;
    $H /= 360.0;

    return ( $H, $S, $L );

}

# h, s, l = [0,1), [0,1], [0,1]
# returns: rgb: [0,255], [0,255], [0,255]
sub hsl_to_rgb {
    my ( $H, $S, $L ) = @_;

    # gray.
    if ( $S < 0.0000000000001 ) {
        my $gv = int( 255 * $L + 0.5 );
        return ( $gv, $gv, $gv );
    }

    my ( $t1, $t2 );
    if ( $L < 0.5 ) {
        $t2 = $L * ( 1.0 + $S );
    }
    else {
        $t2 = $L + $S - $L * $S;
    }
    $t1 = 2.0 * $L - $t2;

    my $fromhue = sub {
        my $hue = shift;
        if ( $hue < 0 ) { $hue += 1.0; }
        if ( $hue > 1 ) { $hue -= 1.0; }

        if ( 6.0 * $hue < 1 ) {
            return $t1 + ( $t2 - $t1 ) * $hue * 6.0;
        }
        elsif ( 2.0 * $hue < 1 ) {
            return $t2;
        }
        elsif ( 3.0 * $hue < 2.0 ) {
            return ( $t1 + ( $t2 - $t1 ) * ( ( 2.0 / 3.0 ) - $hue ) * 6.0 );
        }
        else {
            return $t1;
        }
    };

    return map { int( 255 * $fromhue->($_) + 0.5 ) } ( $H + 1.0 / 3.0, $H, $H - 1.0 / 3.0 );
}

1;
