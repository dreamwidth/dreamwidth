package LJ::S2Theme::fluidmeasure;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "branchandroot" }

package LJ::S2Theme::fluidmeasure::nnwm2009;
use base qw( LJ::S2Theme::fluidmeasure );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::fluidmeasure::nutmeg;
use base qw( LJ::S2Theme::fluidmeasure );
sub cats { qw() }

package LJ::S2Theme::fluidmeasure::spice;
use base qw( LJ::S2Theme::fluidmeasure );
sub cats { qw( base featured ) }

package LJ::S2Theme::fluidmeasure::summerdark;
use base qw( LJ::S2Theme::fluidmeasure );
sub cats { qw() }

package LJ::S2Theme::fluidmeasure::wooded;
use base qw( LJ::S2Theme::fluidmeasure );
sub cats { qw() }

1;

