package LJ::S2Theme::funkycircles;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "900degrees" }


package LJ::S2Theme::funkycircles::atomicorange;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw( ) }

package LJ::S2Theme::funkycircles::chocolaterose;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw( ) }

package LJ::S2Theme::funkycircles::darkblue;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw( ) }

package LJ::S2Theme::funkycircles::darkpurple;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw( featured base ) }

package LJ::S2Theme::funkycircles::earthygreen;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw( ) }

package LJ::S2Theme::funkycircles::industrialpink;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw( ) }

package LJ::S2Theme::funkycircles::industrialteal;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw( ) }

package LJ::S2Theme::funkycircles::seablues;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw( ) }

1;
