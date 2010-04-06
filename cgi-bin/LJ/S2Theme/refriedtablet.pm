package LJ::S2Theme::refriedtablet;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "zvi" }

package LJ::S2Theme::refriedtablet::autumnnight;
use base qw( LJ::S2Theme::refriedtablet );
sub cats { qw(  ) }

package LJ::S2Theme::refriedtablet::californiaroll;
use base qw( LJ::S2Theme::refriedtablet );
sub cats { qw(  ) }

package LJ::S2Theme::refriedtablet::cherryicing;
use base qw( LJ::S2Theme::refriedtablet );
sub cats { qw(  ) }

package LJ::S2Theme::refriedtablet::refriedclassic;
use base qw( LJ::S2Theme::refriedtablet );
sub cats { qw( base ) }


package LJ::S2Theme::refriedtablet::seeded;
use base qw( LJ::S2Theme::refriedtablet );
sub cats { qw( featured ) }

1;

