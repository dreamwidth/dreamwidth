package LJ::S2Theme::nouveauoleanders;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "branchandroot" }

package LJ::S2Theme::nouveauoleanders::dustyantique;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw() }

package LJ::S2Theme::nouveauoleanders::huntergreen;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw() }
sub designer { "dancing_serpent" }

package LJ::S2Theme::nouveauoleanders::piquant;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw() }

package LJ::S2Theme::nouveauoleanders::seaandsalt;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw( featured ) }

package LJ::S2Theme::nouveauoleanders::sienna;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw( base ) }

package LJ::S2Theme::nouveauoleanders::wisteria;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw() }

1;
