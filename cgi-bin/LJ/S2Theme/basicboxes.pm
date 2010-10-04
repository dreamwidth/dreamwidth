package LJ::S2Theme::basicboxes;
use base qw( LJ::S2Theme );
use strict;

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "branchandroot" }

package LJ::S2Theme::basicboxes::acidic;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw( featured ) }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::basicboxes::burgundy;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw() }

package LJ::S2Theme::basicboxes::denim;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw() }

package LJ::S2Theme::basicboxes::ecru;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw() }

package LJ::S2Theme::basicboxes::eggplant;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw() }
sub designer { "kareila" }

package LJ::S2Theme::basicboxes::green;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw() }

package LJ::S2Theme::basicboxes::freshwater;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw( featured ) }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::basicboxes::leaf;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw() }

package LJ::S2Theme::basicboxes::manilaenvelope;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::basicboxes::parchmentandink;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw( featured ) }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::basicboxes::peach;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw() }

package LJ::S2Theme::basicboxes::pleasantneutrality;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw( featured ) }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::basicboxes::poppyfields;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw( featured ) }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::basicboxes::repose;
use base qw( LJ::S2Theme::basicboxes );
sub cats { qw() }
sub designer { "twtd" }

1;
