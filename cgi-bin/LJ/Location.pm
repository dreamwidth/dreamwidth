package LJ::Location;
use strict;
use warnings;

use Math::Trig qw(deg2rad);

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;

    my $coords = delete $opts{'coords'};
    my $loc    = delete $opts{'location'};
    die if %opts;

    $self->set_coords($coords)   if $coords;
    $self->set_location($loc)    if $loc;
    return $self;
}

sub set_location {
    my ($self, $loc) = @_;
    $self->{location} = $loc;
    return $self;
}

sub set_coords {
    my ($self, $coords) = @_;
    my ($lat, $long);
    if ($coords =~ /^(\d+\.\d+)\s*([NS])\s*,?\s*(\d+\.\d+)\s*([EW])$/i) {
        my ($latpos, $latside, $longpos, $longside) = ($1, uc $2, $3, uc $4);
        $lat  =  $latpos;
        $lat  = -$latpos if $latside eq "S";
        $long =  $longpos;
        $long = -$longpos if $longside eq "W";
    } elsif ($coords =~ /^(-?\d+\.\d+)\s*\,?\s*(-?\d+\.\d+)$/) {
        $lat  = $1;
        $long = $2;
    } else {
        die "Invalid coords format";
    }

    die "Latitude out of range"  if abs $lat > 90;
    die "Longitude out of range" if abs $long > 180;
    $self->{lat}      = $lat;
    $self->{long}     = $long;
    return $self;
}

sub coordinates  {
    my $self = shift;
    return $self->{lat}, $self->{long};
}

sub as_posneg_comma {
    my $self = shift;
    return undef unless $self->{lat} || $self->{long};
    return sprintf("%0.04f,%0.04f", $self->{lat}, $self->{long});
}

sub as_html_current {
    my $self = shift;
    my $e_text = LJ::ehtml($self->{location} || $self->as_posneg_comma);
    my $e_mapquery = LJ::eurl($self->as_posneg_comma || $self->{location});
    my $map_service = $LJ::MAP_SERVICE || "http://maps.google.com/maps?q=";
    return "<a href='$map_service$e_mapquery'>$e_text</a>";
}

# Average of polar and equatorial radius of the earth
sub EARTH_RADIUS_KILOMETERS () { 6371.005 }
sub EARTH_RADIUS_MILES      () { 3958.759 }

sub _haversine_distance {
    my ($lat1, $lon1, $lat2, $lon2) = map { deg2rad($_) } @_;

    my $dlon = $lon2 - $lon1;
    my $dlat = $lat2 - $lat1;
    my $a = (sin($dlat/2)) ** 2 + cos($lat1) * cos($lat2) * (sin($dlon/2)) ** 2;
    return 2 * atan2(sqrt($a), sqrt(1-$a));
}

sub kilometers_to {
    my $loc = shift;
    my $loc2 = shift;
    return EARTH_RADIUS_KILOMETERS * _haversine_distance( $loc->coordinates, $loc2->coordinates );
}

sub miles_to {
    my $loc = shift;
    my $loc2 = shift;
    return EARTH_RADIUS_MILES * _haversine_distance( $loc->coordinates, $loc2->coordinates );
}

1;
