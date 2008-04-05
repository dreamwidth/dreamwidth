package LJ::S2Theme::magazine;
use base qw(LJ::S2Theme);

sub cats { qw( clean cool ) }
sub designer { "lucent" }

sub display_option_props {
    my $self = shift;
    my @props = qw( content_alignment );
    return $self->_append_props("display_option_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( main_fgcolor highlight_bgcolor highlight_fgcolor link_color vlink_color alink_color );
    return $self->_append_props("text_props", @props);
}

sub header_bar_props {
    my $self = shift;
    my @props = qw( headerbar_bgcolor headerbar_fgcolor headerbar_bevel_color );
    return $self->_append_props("header_bar_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw( date_format time_format );
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

package LJ::S2Theme::magazine::ashfire;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean warm ) }

package LJ::S2Theme::magazine::brownleather;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean warm nature ) }

package LJ::S2Theme::magazine::desktop;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean warm ) }

package LJ::S2Theme::magazine::everblue;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean cool ) }
sub designer { "everdred" }

package LJ::S2Theme::magazine::everwhite;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean ) }
sub designer { "everdred" }

package LJ::S2Theme::magazine::forest;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean cool nature ) }

package LJ::S2Theme::magazine::lowercurtain;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean dark ) }

package LJ::S2Theme::magazine::mexicanfood;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean warm ) }

package LJ::S2Theme::magazine::satinhandshake;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean warm ) }

package LJ::S2Theme::magazine::stripes;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean ) }

package LJ::S2Theme::magazine::sunny;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean warm ) }

package LJ::S2Theme::magazine::valentine;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean warm ) }

package LJ::S2Theme::magazine::wonb;
use base qw(LJ::S2Theme::magazine);
sub cats { qw( clean dark ) }

1;
