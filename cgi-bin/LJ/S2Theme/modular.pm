package LJ::S2Theme::modular;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "branchandroot" }

package LJ::S2Theme::modular::amberandgreen;
use base qw( LJ::S2Theme::modular );
sub cats { qw() }

package LJ::S2Theme::modular::bubblegum;
use base qw( LJ::S2Theme::modular );
sub cats { qw() }

package LJ::S2Theme::modular::coffeeandcream;
use base qw( LJ::S2Theme::modular );
sub cats { qw() }

package LJ::S2Theme::modular::distinctblue;
use base qw( LJ::S2Theme::modular );
sub cats { qw() }

package LJ::S2Theme::modular::freshprose;
use base qw( LJ::S2Theme::modular );
sub cats { qw() }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::modular::greensummer;
use base qw( LJ::S2Theme::modular );
sub cats { qw ( featured ) }

package LJ::S2Theme::modular::irisatdusk;
use base qw( LJ::S2Theme::modular );
sub cats { qw() }

package LJ::S2Theme::modular::mediterraneanpeach;
use base qw( LJ::S2Theme::modular );
sub cats { qw() }

package LJ::S2Theme::modular::olivetree;
use base qw( LJ::S2Theme::modular );
sub cats { qw() }

package LJ::S2Theme::modular::purplehaze;
use base qw( LJ::S2Theme::modular );
sub cats { qw() }
sub designer { "timeasmymeasure" }

package LJ::S2Theme::modular::swiminthesea;
use base qw( LJ::S2Theme::modular );
sub cats { qw() }

1;
