package LJ::S2Theme::classic;
use base qw(LJ::S2Theme);

sub cats { qw( clean cool ) }

sub display_option_props {
    my $self = shift;
    my @props = qw( counter_code );
    return $self->_append_props("display_option_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( link_color vlink_color alink_color );
    return $self->_append_props("text_props", @props);
}

sub header_bar_props {
    my $self = shift;
    my @props = qw( headerbar_bgcolor headerbar_fgcolor );
    return $self->_append_props("header_bar_props", @props);
}

sub sidebar_props {
    my $self = shift;
    my @props = qw( metabar_bgcolor metabar_fgcolor );
    return $self->_append_props("sidebar_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw( text_left_comments text_btwn_comments text_right_comments date_format time_format datetime_comments_format );
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

package LJ::S2Theme::classic::ashfire;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean warm ) }

package LJ::S2Theme::classic::brownleather;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean warm nature ) }

package LJ::S2Theme::classic::calmfire;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean warm ) }

package LJ::S2Theme::classic::desktop;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean warm ) }

package LJ::S2Theme::classic::everblue;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean cool ) }
sub designer { "everdred" }

package LJ::S2Theme::classic::everwhite;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean ) }
sub designer { "everdred" }

package LJ::S2Theme::classic::forest;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean cool nature ) }

package LJ::S2Theme::classic::lowercurtain;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean dark ) }

package LJ::S2Theme::classic::mexicanfood;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean warm ) }

package LJ::S2Theme::classic::satinhandshake;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean warm ) }

package LJ::S2Theme::classic::stripes;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean ) }

package LJ::S2Theme::classic::sunny;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean warm ) }

package LJ::S2Theme::classic::valentine;
use base qw(LJ::S2Theme::classic);
sub cats { qw( clean warm ) }

1;
