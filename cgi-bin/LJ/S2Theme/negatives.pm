package LJ::S2Theme::negatives;
use base qw( LJ::S2Theme );

sub cats { qw( featured ) }
sub designer { "phoenixdreaming" }

sub layouts { ( "2r" => "two-columns-right" ) }
sub layout_prop { "layout_type" }
1;