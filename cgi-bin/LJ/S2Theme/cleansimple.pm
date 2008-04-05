package LJ::S2Theme::cleansimple;
use base qw(LJ::S2Theme);

sub layouts { ( "2l" => "left", "2r" => "right" ) }
sub layout_prop { "opt_navbar_pos" }
sub cats { qw( clean cool ) }
sub designer { "Martin Atkins" }

sub display_option_props {
    my $self = shift;
    my @props = qw( counter_code );
    return $self->_append_props("display_option_props", @props);
}

sub navigation_props {
    my $self = shift;
    my @props = qw( font_sidebar_base font_sidebar_fallback );
    return $self->_append_props("navigation_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( link_color vlink_color alink_color );
    return $self->_append_props("text_props", @props);
}

sub top_bar_props {
    my $self = shift;
    my @props = qw( font_topbar_base font_topbar_fallback );
    return $self->_append_props("top_bar_props", @props);
}

sub sidebar_props {
    my $self = shift;
    my @props = qw( navbar_bgcolor navbar_fgcolor );
    return $self->_append_props("sidebar_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw(
        entry_bgcolor entry_fgcolor meta_color border_color opt_text_left_comments
        opt_text_btwn_comments opt_text_right_comments date_format time_format datetime_format
    );
    return $self->_append_props("entry_props", @props);
}

sub comment_props {
    my $self = shift;
    my @props = qw(
        comment_bar_one_bgcolor comment_bar_two_fgcolor comment_bar_two_bgcolor
        comment_bar_one_fgcolor comment_bar_screened_bgcolor comment_bar_screened_fgcolor
    );
    return $self->_append_props("comment_props", @props);
}


### Themes ###

package LJ::S2Theme::cleansimple::ashfire;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( clean warm ) }

package LJ::S2Theme::cleansimple::brownleather;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( clean warm nature ) }

package LJ::S2Theme::cleansimple::desktop;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( clean warm ) }

package LJ::S2Theme::cleansimple::everblue;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( clean cool ) }
sub designer { "everdred" }

package LJ::S2Theme::cleansimple::everwhite;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( clean ) }
sub designer { "everdred" }

package LJ::S2Theme::cleansimple::flesh;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( clean warm ) }

package LJ::S2Theme::cleansimple::forest;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( nature ) }

package LJ::S2Theme::cleansimple::lowercurtain;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( clean dark ) }

package LJ::S2Theme::cleansimple::mexicanfood;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( clean warm ) }

package LJ::S2Theme::cleansimple::satinhandshake;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( clean warm ) }

package LJ::S2Theme::cleansimple::stripes;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( clean ) }

package LJ::S2Theme::cleansimple::sunny;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( clean warm ) }

package LJ::S2Theme::cleansimple::valentine;
use base qw(LJ::S2Theme::cleansimple);
sub cats { qw( clean warm ) }

1;
