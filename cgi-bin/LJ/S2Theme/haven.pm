package LJ::S2Theme::haven;
use base qw(LJ::S2Theme);

sub layouts { ( "2l" => "left", "2r" => "right" ) }
sub layout_prop { "sidebar_position" }
sub cats { qw( clean modern ) }
sub designer { "Jesse Proulx" }
sub linklist_support_tab { "Sidebar" }

sub display_option_props {
    my $self = shift;
    my @props = qw( show_entry_userpic );
    return $self->_append_props("display_option_props", @props);
}

sub navigation_box_props {
    my $self = shift;
    my @props = qw( nav_bgcolor nav_fgcolor );
    return $self->_append_props("navigation_box_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( page_fgcolor );
    return $self->_append_props("text_props", @props);
}

sub title_box_props {
    my $self = shift;
    my @props = qw( title_bgcolor title_fgcolor title_border );
    return $self->_append_props("title_box_props", @props);
}

sub tabs_and_headers_props {
    my $self = shift;
    my @props = qw( tabs_bgcolor tabs_fgcolor );
    return $self->_append_props("tabs_and_headers_props", @props);
}

sub sidebar_props {
    my $self = shift;
    my @props = qw(
        sidebar_box_bgcolor sidebar_box_fgcolor sidebar_box_title_bgcolor sidebar_box_title_fgcolor
        sidebar_box_border sidebar_font sidebar_font_fallback
    );
    return $self->_append_props("sidebar_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw(
        content_bgcolor content_fgcolor content_border content_font content_font_fallback
        text_meta_music text_meta_mood text_meta_location text_meta_groups
    );
    return $self->_append_props("entry_props", @props);
}

sub comment_props {
    my $self = shift;
    my @props = qw(
        comment_bar_one_bgcolor comment_bar_one_fgcolor comment_bar_two_bgcolor comment_bar_two_fgcolor comment_bar_screened_bgcolor
        comment_bar_screened_fgcolor text_post_comment text_read_comments text_post_comment_friends text_read_comments_friends 
    );
    return $self->_append_props("comment_props", @props);
}

sub hotspot_area_props {
    my $self = shift;
    my @props = qw( accent_bgcolor accent_fgcolor );
    return $self->_append_props("hotspot_area_props", @props);
}

sub setup_props {
    my $self = shift;
    my @props = qw( sidebar_width sidebar_blurb );
    return $self->_append_props("setup_props", @props);
}

sub ordering_props {
    my $self = shift;
    my @props = qw( sidebar_position_one sidebar_position_two sidebar_position_three sidebar_position_four );
    return $self->_append_props("ordering_props", @props);
}


### Themes ###

package LJ::S2Theme::haven::bluecomplementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( modern ) }

package LJ::S2Theme::haven::bluedouble_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( cool modern ) }

package LJ::S2Theme::haven::bluesplit_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( cool modern ) }

package LJ::S2Theme::haven::bluetetradic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( cool modern ) }

package LJ::S2Theme::haven::greendouble_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( cool modern ) }

package LJ::S2Theme::haven::greensplit_complementary;
use base qw(LJ::S2Theme::haven);
sub cats { qw( cool modern ) }

package LJ::S2Theme::haven::greentriadic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( cool modern ) }

package LJ::S2Theme::haven::indigoblue;
use base qw(LJ::S2Theme::haven);
sub cats { qw( clean cool modern ) }

package LJ::S2Theme::haven::orangeanalogous;
use base qw(LJ::S2Theme::haven);
sub cats { qw( modern nature ) }

package LJ::S2Theme::haven::orangemonochromatic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( modern ) }

package LJ::S2Theme::haven::redanalogous;
use base qw(LJ::S2Theme::haven);
sub cats { qw( cool modern ) }

package LJ::S2Theme::haven::redmonochromatic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( cool modern ) }

package LJ::S2Theme::haven::violetanalogous;
use base qw(LJ::S2Theme::haven);
sub cats { qw( cool modern ) }

package LJ::S2Theme::haven::yellowanalogous;
use base qw(LJ::S2Theme::haven);
sub cats { qw( cool modern nature ) }

package LJ::S2Theme::haven::yellowmonochromatic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( modern nature ) }

package LJ::S2Theme::haven::yellowtriadic;
use base qw(LJ::S2Theme::haven);
sub cats { qw( modern ) }

1;
