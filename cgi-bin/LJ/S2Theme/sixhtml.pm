package LJ::S2Theme::sixhtml;
use base qw(LJ::S2Theme);

sub layouts { ( "1" => "1C", "2l" => "2CL", "2r" => "2CR", "3m" => "3C" ) }
sub layout_prop { "layout_type" }
sub cats { qw( clean cool ) }
sub designer { "Lilia Ahner" }

sub display_option_props {
    my $self = shift;
    my @props = qw( opt_showtime );
    return $self->_append_props("display_option_props", @props);
}

sub navigation_props {
    my $self = shift;
    my @props = qw( text_view_recent text_view_archive text_view_friends text_view_userinfo );
    return $self->_append_props("navigation_props", @props);
}


### Themes ###

package LJ::S2Theme::sixhtml::__none;
use base qw(LJ::S2Theme::sixhtml);
sub cats { () }
sub designer { "" }

package LJ::S2Theme::sixhtml::april;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( clean cool ) }
sub designer { "" }

package LJ::S2Theme::sixhtml::baby;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( animals cute illustrated occasions ) }

package LJ::S2Theme::sixhtml::beckett;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( dark modern ) }

package LJ::S2Theme::sixhtml::bluecrush;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( cool modern ) }

package LJ::S2Theme::sixhtml::bonjour;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( clean cute ) }
sub designer { "" }

package LJ::S2Theme::sixhtml::classy;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( clean ) }
sub designer { "" }

package LJ::S2Theme::sixhtml::earth;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( clean cool ) }
sub designer { "" }

package LJ::S2Theme::sixhtml::folio;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( dark modern ) }
sub designer { "Dave Shea" }

package LJ::S2Theme::sixhtml::forestgreen;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( hobbies modern nature ) }
sub designer { "Dave Shea" }

package LJ::S2Theme::sixhtml::green;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( clean cool nature ) }
sub designer { "Dave Shea" }

package LJ::S2Theme::sixhtml::knitting;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( cute hobbies ) }

package LJ::S2Theme::sixhtml::masala;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( warm modern ) }

package LJ::S2Theme::sixhtml::minimalist;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( clean ) }
sub designer { "" }

package LJ::S2Theme::sixhtml::porpoise;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( cool cute modern ) }
sub designer { "Dave Shea" }

package LJ::S2Theme::sixhtml::powell_street;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( cool modern ) }

package LJ::S2Theme::sixhtml::stitch;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( clean warm ) }

package LJ::S2Theme::sixhtml::sunburned;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( warm modern ) }
sub designer { "David Shea" }

package LJ::S2Theme::sixhtml::travel;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( cool cute modern travel ) }

package LJ::S2Theme::sixhtml::wedding;
use base qw(LJ::S2Theme::sixhtml);
sub cats { qw( cool cute modern ) }

1;
