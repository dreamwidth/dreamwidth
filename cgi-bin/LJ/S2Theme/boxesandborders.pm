package LJ::S2Theme::boxesandborders;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "branchandroot" }


package LJ::S2Theme::boxesandborders::bittersweet;
use base qw( LJ::S2Theme::boxesandborders );
sub cats { qw( ) }

package LJ::S2Theme::boxesandborders::grass;
use base qw( LJ::S2Theme::boxesandborders );
sub cats { qw( ) }

package LJ::S2Theme::boxesandborders::gray;
use base qw( LJ::S2Theme::boxesandborders );
sub cats { qw( base ) }

sub designer { "branchandroot" }

package LJ::S2Theme::boxesandborders::lightondark;
use base qw( LJ::S2Theme::boxesandborders );
sub cats { qw( ) }

sub designer { "cesy" }

package LJ::S2Theme::boxesandborders::nnwm2009;
use base qw( LJ::S2Theme::boxesandborders );
sub cats { qw() }

sub designer { "zvi" }

package LJ::S2Theme::boxesandborders::onfire;
use base qw( LJ::S2Theme::boxesandborders );
sub cats { qw( ) }

package LJ::S2Theme::boxesandborders::pinkafterdark;
use base qw( LJ::S2Theme::boxesandborders );
sub cats { qw( ) }

package LJ::S2Theme::boxesandborders::rainyday;
use base qw( LJ::S2Theme::boxesandborders );
sub cats { qw( ) }

1;
