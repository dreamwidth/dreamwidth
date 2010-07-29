package LJ::S2Theme::steppingstones;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "branchandroot" }

package LJ::S2Theme::steppingstones::chocolate;
use base qw( LJ::S2Theme::steppingstones );
sub cats { qw() }

package LJ::S2Theme::steppingstones::cleargreen;
use base qw( LJ::S2Theme::steppingstones );
sub cats { qw() }
sub designer { "ambrya" }

package LJ::S2Theme::steppingstones::duskyrose;
use base qw( LJ::S2Theme::steppingstones );
sub cats { qw() }

package LJ::S2Theme::steppingstones::gray;
use base qw( LJ::S2Theme::steppingstones );
sub cats { qw() }

package LJ::S2Theme::steppingstones::nnwm2009;
use base qw( LJ::S2Theme::steppingstones );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::steppingstones::olive;
use base qw( LJ::S2Theme::steppingstones );
sub cats { qw() }

package LJ::S2Theme::steppingstones::pool;
use base qw( LJ::S2Theme::steppingstones );
sub cats { qw() }

package LJ::S2Theme::steppingstones::purple;
use base qw( LJ::S2Theme::steppingstones );
sub cats { qw() }

package LJ::S2Theme::steppingstones::shadows;
use base qw( LJ::S2Theme::steppingstones );
sub cats { qw() }

package LJ::S2Theme::steppingstones::sunset;
use base qw( LJ::S2Theme::steppingstones );
sub cats { qw() }

1;
