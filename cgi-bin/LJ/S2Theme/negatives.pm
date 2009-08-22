package LJ::S2Theme::negatives;
use base qw( LJ::S2Theme );

sub cats { qw( featured ) }
sub designer { "phoenix" }

sub layouts { ( "2r" => "two-columns-right" ) }
sub layout_prop { "layout_type" }


package LJ::S2Theme::negatives::blastedsands;
use base qw( LJ::S2Theme::negatives );

sub cats { qw() }
sub designer { "zvi" }

1;
