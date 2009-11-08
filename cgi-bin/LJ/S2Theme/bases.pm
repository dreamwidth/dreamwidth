package LJ::S2Theme::bases;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column", "2r" => "two-columns-right" ) }
sub layout_prop { "layout_type" }

sub designer { "Malionette" }

package LJ::S2Theme::bases::lightondark;
use base qw( LJ::S2Theme::bases );
sub cats { qw( ) }
sub designer { "cesy" }

package LJ::S2Theme::bases::strawberrysundae;
use base qw( LJ::S2Theme::bases );
sub cats { qw() }
sub designer { "sky" }

package LJ::S2Theme::bases::sunandsand;
use base qw( LJ::S2Theme::bases );
sub cats { qw( featured ) }
sub designer { "twtd" }

package LJ::S2Theme::bases::tropical;
use base qw( LJ::S2Theme::bases );
sub cats { qw( base ) }

package LJ::S2Theme::bases::summerholiday;
use base qw( LJ::S2Theme::bases );
sub cats { qw( ) }
sub designer { "rb" }

package LJ::S2Theme::bases::nnwm2009;
use base qw( LJ::S2Theme::bases );
sub cats { qw( ) }
sub designer { "zvi" }



1;

