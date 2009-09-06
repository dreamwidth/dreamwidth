package LJ::S2Theme::bases;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column", "2r" => "two-columns-right" ) }
sub layout_prop { "layout_type" }

sub designer { "Malionette" }


package LJ::S2Theme::bases::tropical;
use base qw( LJ::S2Theme::bases );
sub cats { qw( featured ) }

package LJ::S2Theme::bases::summerholiday;
use base qw( LJ::S2Theme::bases );
sub cats { qw( ) }
sub designer { "rb" }


1;

