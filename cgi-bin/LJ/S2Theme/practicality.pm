package LJ::S2Theme::practicality;
use base qw( LJ::S2Theme );
use strict;

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "timeasmymeasure" }

package LJ::S2Theme::practicality::cherryblossoms;
use base qw( LJ::S2Theme::practicality );
sub cats { qw() }

package LJ::S2Theme::practicality::chococraze;
use base qw( LJ::S2Theme::practicality );
sub cats { qw() }

package LJ::S2Theme::practicality::neutralgood;
use base qw( LJ::S2Theme::practicality );
sub cats { qw() }

package LJ::S2Theme::practicality::nightlight;
use base qw( LJ::S2Theme::practicality );
sub cats { qw() }

package LJ::S2Theme::practicality::poppyfields;
use base qw( LJ::S2Theme::practicality );
sub cats { qw() }

package LJ::S2Theme::practicality::warmth;
use base qw( LJ::S2Theme::practicality );
sub cats { qw( base ) }

1;
