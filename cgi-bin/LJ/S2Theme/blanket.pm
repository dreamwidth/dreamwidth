package LJ::S2Theme::blanket;
use base qw( LJ::S2Theme );
use strict;

sub layouts     { ( "1" => "one-column" ) }
sub layout_prop { "layout_type" }

1;
