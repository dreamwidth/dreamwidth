package LJ::S2Theme::colorside;
use base qw( LJ::S2Theme );
use strict;

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "branchandroot" }

package LJ::S2Theme::colorside::bedrock;
use base qw( LJ::S2Theme::colorside );
sub cats { qw( featured ) }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::colorside::colorblockade;
use base qw( LJ::S2Theme::colorside );
sub cats { qw( featured ) }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::colorside::lightondark;
use base qw( LJ::S2Theme::colorside );
sub cats { qw() }
sub designer { "cesy" }

package LJ::S2Theme::colorside::nnwm2009;
use base qw( LJ::S2Theme::colorside );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::colorside::nnwm2010fresh;
use base qw( LJ::S2Theme::colorside );
sub cats { qw() }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::colorside::nnwm2010warmth;
use base qw( LJ::S2Theme::colorside );
sub cats { qw() }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::colorside::scatteredfields;
use base qw( LJ::S2Theme::colorside );
sub cats { qw( featured ) }
sub designer { "timeasmymeasure" }

1;
