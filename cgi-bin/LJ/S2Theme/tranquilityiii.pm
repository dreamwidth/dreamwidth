package LJ::S2Theme::tranquilityiii;
use base qw( LJ::S2Theme );
use strict;

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "branchandroot" }

package LJ::S2Theme::tranquilityiii::brick;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }

package LJ::S2Theme::tranquilityiii::clearmessages;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::tranquilityiii::deeppurple;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }
sub designer { "dancing_serpent" }

package LJ::S2Theme::tranquilityiii::freshblue;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }
sub designer { "forthwritten" }

package LJ::S2Theme::tranquilityiii::lightondark;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }
sub designer { "cesy" }

package LJ::S2Theme::tranquilityiii::lilac;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }

package LJ::S2Theme::tranquilityiii::marbleiii;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }
sub designer { "dancing_serpent" }

package LJ::S2Theme::tranquilityiii::nightsea;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }

package LJ::S2Theme::tranquilityiii::nnwm2009;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::tranquilityiii::olive;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }
sub designer { "dancing_serpent" }

package LJ::S2Theme::tranquilityiii::seadeep;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::tranquilityiii::shallows;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }
sub designer { "dancing_serpent" }

package LJ::S2Theme::tranquilityiii::stonemask;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::tranquilityiii::wintergreen;
use base qw( LJ::S2Theme::tranquilityiii );
sub cats { qw() }
sub designer { "dancing_serpent" }

1;
