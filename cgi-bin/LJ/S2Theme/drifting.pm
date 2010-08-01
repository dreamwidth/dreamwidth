package LJ::S2Theme::drifting;
use base qw( LJ::S2Theme );

sub layouts { ( "2l" => "two-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "Jennie Griner" }

package LJ::S2Theme::drifting::chocolatecherry;
use base qw( LJ::S2Theme::drifting );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::drifting::comfortzone;
use base qw( LJ::S2Theme::drifting );
sub cats { qw() }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::drifting::desertme;
use base qw( LJ::S2Theme::drifting );
sub cats { qw() }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::drifting::go;
use base qw( LJ::S2Theme::drifting );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::drifting::idolatry;
use base qw( LJ::S2Theme::drifting );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::drifting::lightondark;
use base qw( LJ::S2Theme::drifting );
sub cats { qw() }
sub designer { "cesy" }

package LJ::S2Theme::drifting::softblues;
use base qw( LJ::S2Theme::drifting );
sub cats { qw() }
sub designer { "ambrya" }

package LJ::S2Theme::drifting::sweetpossibilities;
use base qw( LJ::S2Theme::drifting );
sub cats { qw( featured ) }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::drifting::winterclarity;
use base qw( LJ::S2Theme::drifting );
sub cats { qw() }
sub designer { "timeasmymeasure" }

1;
