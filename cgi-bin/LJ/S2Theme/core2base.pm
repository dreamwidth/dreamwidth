package LJ::S2Theme::core2base;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

package LJ::S2Theme::core2base::dazzle;
use base qw( LJ::S2Theme::core2base );
sub cats { qw(  ) }
sub designer { "zvi" }

package LJ::S2Theme::core2base::kelis;
use base qw( LJ::S2Theme::core2base );
sub cats { qw( featured ) }        
sub designer { "zvi" }

package LJ::S2Theme::core2base::muted;
use base qw( LJ::S2Theme::core2base );
sub cats { qw( ) }        
sub designer { "zvi" }

package LJ::S2Theme::core2base::nnwm2009;
use base qw( LJ::S2Theme::core2base );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::core2base::shanice;
use base qw( LJ::S2Theme::core2base );
sub cats { qw() }        
sub designer { "zvi" }

package LJ::S2Theme::core2base::tabac;
use base qw( LJ::S2Theme::core2base );
sub cats { qw(  ) }        
sub designer { "zvi" }

package LJ::S2Theme::core2base::testing;
use base qw( LJ::S2Theme::core2base );
sub cats { qw( base )}
1;
