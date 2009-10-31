package LJ::S2Theme::negatives;
use base qw( LJ::S2Theme );

sub cats { qw() }
sub designer { "phoenix" }

sub layouts { ( "1" => "one-column", "2r" => "two-columns-right" ) }
sub layout_prop { "layout_type" }

package LJ::S2Theme::negatives::black;
use base qw( LJ::S2Theme::negatives );
sub cats { qw( base ) }

package LJ::S2Theme::negatives::blastedsands;
use base qw( LJ::S2Theme::negatives );
sub cats { qw(featured) }
sub designer { "zvi" }

package LJ::S2Theme::negatives::lightondark;
use base qw( LJ::S2Theme::negatives );
sub cats { qw() }
sub designer { "cesy" }

package LJ::S2Theme::negatives::limecherry;
use base qw( LJ::S2Theme::negatives );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::negatives::nnwm2009;
use base qw( LJ::S2Theme::negatives );
sub cats { qw() }
sub designer { "zvi" }


package LJ::S2Theme::negatives::pumpkinjuice;
use base qw( LJ::S2Theme::negatives );
sub cats { qw() }
sub designer { "zvi" }

1;
