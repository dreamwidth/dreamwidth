package LJ::S2Theme::punquin;
use base qw(LJ::S2Theme);

sub layouts { ( "2lnh" => "left", "2rnh" => "right" ) }
sub layout_prop { "sidebar_position" }
sub cats { qw( clean cool ) }
sub designer { "punquin" }

sub display_option_props {
    my $self = shift;
    my @props = qw( show_recent_userpic );
    return $self->_append_props("display_option_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( main_fgcolor link_color vlink_color alink_color );
    return $self->_append_props("text_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw( subject_color title_color border_color border_color_entries date_format time_format );
    return $self->_append_props("entry_props", @props);
}

sub comment_props {
    my $self = shift;
    my @props = qw(
        comment_bar_one_bgcolor comment_bar_two_fgcolor comment_bar_two_bgcolor comment_bar_one_fgcolor comment_bar_screened_bgcolor
        comment_bar_screened_fgcolor text_post_comment text_read_comments text_post_comment_friends text_read_comments_friends
        text_left_comments text_btwn_comments text_right_comments datetime_comments_format
    );
    return $self->_append_props("comment_props", @props);
}


### Themes ###

package LJ::S2Theme::punquin::ashfire;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean warm ) }

package LJ::S2Theme::punquin::autumn;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean warm nature ) }

package LJ::S2Theme::punquin::brownleather;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean warm nature ) }

package LJ::S2Theme::punquin::bw;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean ) }

package LJ::S2Theme::punquin::desktop;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean warm ) }

package LJ::S2Theme::punquin::everblue;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean cool dark ) }
sub designer { "everdred" }

package LJ::S2Theme::punquin::everwhite;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean ) }
sub designer { "everdred" }

package LJ::S2Theme::punquin::forest;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean cool nature ) }

package LJ::S2Theme::punquin::greyslate;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean cool nature ) }

package LJ::S2Theme::punquin::jewel;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean warm nature ) }

package LJ::S2Theme::punquin::lowercurtain;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean dark ) }

package LJ::S2Theme::punquin::mexicanfood;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean warm ) }

package LJ::S2Theme::punquin::minimal;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean ) }

package LJ::S2Theme::punquin::satinhandshake;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean warm ) }

package LJ::S2Theme::punquin::stripes;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean ) }

package LJ::S2Theme::punquin::sunny;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean warm ) }

package LJ::S2Theme::punquin::valentine;
use base qw(LJ::S2Theme::punquin);
sub cats { qw( clean warm ) }

1;
