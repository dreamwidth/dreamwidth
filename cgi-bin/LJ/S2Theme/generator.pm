package LJ::S2Theme::generator;
use base qw(LJ::S2Theme);

sub cats { qw( clean cool ) }
sub designer { "evan" }

sub display_option_props {
    my $self = shift;
    my @props = qw( comment_userpic_style );
    return $self->_append_props("display_option_props", @props);
}

sub navigation_props {
    my $self = shift;
    my @props = qw( text_navlinks_left text_navlinks_btwn text_navlinks_right );
    return $self->_append_props("navigation_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( page_link page_vlink page_alink );
    return $self->_append_props("text_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw(
        text_meta_music text_meta_mood text_meta_location text_meta_groups entry_back entry_text
        comment_bar_screened_bgcolor comment_bar_screened_fgcolor date_format time_format btwn_datetime
    );
    return $self->_append_props("entry_props", @props);
}

sub comment_props {
    my $self = shift;
    my @props = qw(
        text_post_comment text_read_comments text_post_comment_friends text_read_comments_friends
        comment_bar_one_bgcolor comment_bar_two_fgcolor comment_bar_two_bgcolor comment_bar_one_fgcolor
        text_left_comments text_btwn_comments text_right_comments datetime_comments_format
    );
    return $self->_append_props("comment_props", @props);
}


### Themes ###

package LJ::S2Theme::generator::bananapeel;
use base qw(LJ::S2Theme::generator);
sub cats { qw( clean warm ) }

package LJ::S2Theme::generator::elegant;
use base qw(LJ::S2Theme::generator);
sub cats { qw( clean ) }

package LJ::S2Theme::generator::everblue;
use base qw(LJ::S2Theme::generator);
sub cats { qw( clean cool dark ) }
sub designer { "everdred" }

package LJ::S2Theme::generator::everwhite;
use base qw(LJ::S2Theme::generator);
sub designer { "everdred" }

package LJ::S2Theme::generator::harvest;
use base qw(LJ::S2Theme::generator);
sub cats { qw( clean warm ) }

package LJ::S2Theme::generator::jeweled;
use base qw(LJ::S2Theme::generator);
sub cats { qw( clean cool ) }

package LJ::S2Theme::generator::redbliss;
use base qw(LJ::S2Theme::generator);
sub cats { qw( clean warm ) }

package LJ::S2Theme::generator::satin;
use base qw(LJ::S2Theme::generator);
sub cats { qw( clean warm dark ) }

package LJ::S2Theme::generator::sunset;
use base qw(LJ::S2Theme::generator);
sub cats { qw( clean warm ) }

1;
