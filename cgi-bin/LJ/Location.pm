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

package LJ::Location;
use strict;
use warnings;

use Math::Trig qw(deg2rad);

sub new {
    my ( $class, %opts ) = @_;
    my $self = bless {}, $class;

    my $coords = delete $opts{'coords'};
    my $loc    = delete $opts{'location'};
    die if %opts;

    $self->set_coords($coords) if $coords;
    $self->set_location($loc)  if $loc;
    return $self;
}

sub set_location {
    my ( $self, $loc ) = @_;
    $self->{location} = $loc;
    return $self;
}

sub set_coords {
    my ( $self, $coords ) = @_;
    my ( $lat, $long );
    if ( $coords =~ /^(\d+\.\d+)\s*([NS])\s*,?\s*(\d+\.\d+)\s*([EW])$/i ) {
        my ( $latpos, $latside, $longpos, $longside ) = ( $1, uc $2, $3, uc $4 );
        $lat  = $latpos;
        $lat  = -$latpos if $latside eq "S";
        $long = $longpos;
        $long = -$longpos if $longside eq "W";
    }
    elsif ( $coords =~ /^(-?\d+\.\d+)\s*\,?\s*(-?\d+\.\d+)$/ ) {
        $lat  = $1;
        $long = $2;
    }
    else {
        die "Invalid coords format";
    }

    die "Latitude out of range"  if abs $lat > 90;
    die "Longitude out of range" if abs $long > 180;
    $self->{lat}  = $lat;
    $self->{long} = $long;
    return $self;
}

sub coordinates {
    my $self = shift;
    return $self->{lat}, $self->{long};
}

sub as_posneg_comma {
    my $self = shift;
    return undef unless $self->{lat} || $self->{long};
    return sprintf( "%0.04f,%0.04f", $self->{lat}, $self->{long} );
}

sub as_current {
    my $self = shift;
    return $self->{location} || $self->as_posneg_comma;
}

# Average of polar and equatorial radius of the earth
sub EARTH_RADIUS_KILOMETERS () { 6371.005 }
sub EARTH_RADIUS_MILES ()      { 3958.759 }

sub _haversine_distance {
    my ( $lat1, $lon1, $lat2, $lon2 ) = map { deg2rad($_) } @_;

    my $dlon = $lon2 - $lon1;
    my $dlat = $lat2 - $lat1;
    my $a    = ( sin( $dlat / 2 ) )**2 + cos($lat1) * cos($lat2) * ( sin( $dlon / 2 ) )**2;
    return 2 * atan2( sqrt($a), sqrt( 1 - $a ) );
}

sub kilometers_to {
    my $loc  = shift;
    my $loc2 = shift;
    return EARTH_RADIUS_KILOMETERS * _haversine_distance( $loc->coordinates, $loc2->coordinates );
}

sub miles_to {
    my $loc  = shift;
    my $loc2 = shift;
    return EARTH_RADIUS_MILES * _haversine_distance( $loc->coordinates, $loc2->coordinates );
}

1;
