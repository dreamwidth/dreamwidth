package LJ::S2Theme::easyread;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column" ) }
sub layout_prop { "layout_type" }

sub designer { "rb" }

package LJ::S2Theme::easyread::clovers;
use base qw( LJ::S2Theme::easyread );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::easyread::green;
use base qw( LJ::S2Theme::easyread );
sub cats { qw() }

package LJ::S2Theme::easyread::hcblack;
use base qw( LJ::S2Theme::easyread );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::easyread::hcblackandyellow;
use base qw( LJ::S2Theme::easyread );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::easyread::hcblueyellow;
use base qw( LJ::S2Theme::easyread );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::easyread::hcwhite;
use base qw( LJ::S2Theme::easyread );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::easyread::lcorange;
use base qw( LJ::S2Theme::easyread );
sub cats { qw( featured ) }
sub designer { "zvi" }

package LJ::S2Theme::easyread::nnwm2009;
use base qw( LJ::S2Theme::easyread );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::easyread::toros;
use base qw( LJ::S2Theme::easyread );
sub cats { qw() }
sub designer { "zvi" }

1;
