package LJ::S2Theme::drifting;
use base qw(LJ::S2Theme);

sub cats { qw( featured base ) }
sub designer { "Jennie Griner" }

sub layouts { ( "2l" => "two-columns-left" ) }
sub layout_prop { "layout_type" }

package LJ::S2Theme::drifting::chocolatecherry;
use base qw( LJ::S2Theme::drifting );

sub cats { qw( ) }
sub designer { "zvi" }
1;
