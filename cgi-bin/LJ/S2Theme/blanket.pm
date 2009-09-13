package LJ::S2Theme::blanket;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column" ) }
sub layout_prop { "layout_type" }

sub designer { "renoir" }


package LJ::S2Theme::blanket::peach;
use base qw( LJ::S2Theme::blanket );
sub cats { qw( featured base ) }

1;

