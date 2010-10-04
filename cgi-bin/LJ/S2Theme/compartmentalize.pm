package LJ::S2Theme::compartmentalize;
use base qw( LJ::S2Theme );
use strict;

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "timeasmymeasure" }

package LJ::S2Theme::compartmentalize::contemplation;
use base qw( LJ::S2Theme::compartmentalize );
sub cats { qw( featured ) }

package LJ::S2Theme::compartmentalize::dawnflush;
use base qw( LJ::S2Theme::compartmentalize );
sub cats { qw( featured ) }

package LJ::S2Theme::compartmentalize::goodsense;
use base qw( LJ::S2Theme::compartmentalize );
sub cats { qw( featured ) }

package LJ::S2Theme::compartmentalize::poppyfields;
use base qw( LJ::S2Theme::compartmentalize );
sub cats { qw( featured ) }

package LJ::S2Theme::compartmentalize::simplicity;
use base qw( LJ::S2Theme::compartmentalize );
sub cats { qw( featured ) }

package LJ::S2Theme::compartmentalize::sweetberrygolds;
use base qw( LJ::S2Theme::compartmentalize );
sub cats { qw( featured ) }

package LJ::S2Theme::compartmentalize::tripout;
use base qw( LJ::S2Theme::compartmentalize );
sub cats { qw( featured ) }

1;
