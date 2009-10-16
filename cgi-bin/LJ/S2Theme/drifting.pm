package LJ::S2Theme::drifting;
use base qw(LJ::S2Theme);

sub cats { qw( base ) }
sub designer { "Jennie Griner" }

sub layouts { ( "2l" => "two-columns-left" ) }
sub layout_prop { "layout_type" }

package LJ::S2Theme::drifting::chocolatecherry;
use base qw( LJ::S2Theme::drifting );

sub cats { qw( featured ) }
sub designer { "zvi" }

package LJ::S2Theme::drifting::idolatry;
use base qw( LJ::S2Theme::drifting );

sub cats { qw( ) }
sub designer { "zvi" }

package LJ::S2Theme::drifting::lightondark;
use base qw( LJ::S2Theme::drifting );

sub cats { qw( ) }
sub designer { "cesy" }
1;
