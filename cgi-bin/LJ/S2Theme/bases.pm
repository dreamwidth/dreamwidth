package LJ::S2Theme::bases;
use base qw( LJ::S2Theme );
use strict;

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right" ) }
sub layout_prop { "layout_type" }

1;
