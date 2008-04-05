package LJ::S2Theme::disjointed;
use base qw(LJ::S2Theme);

sub layouts { ( "2lnh" => "left", "2rnh" => "right" ) }
sub layout_prop { "sidebar_align" }
sub cats { qw( cool modern ) }
sub designer { "adcott" }

sub display_option_props {
    my $self = shift;
    my @props = qw( show_calendar );
    return $self->_append_props("display_option_props", @props);
}

sub navigation_props {
    my $self = shift;
    my @props = qw(
        text_view_recent text_view_friends text_view_friends_comm text_view_archive text_view_userinfo
        text_left_comments text_comment_divider text_right_comments text_back_to_top
    );
    return $self->_append_props("navigation_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( main_link main_vlink main_alink main_hlink );
    return $self->_append_props("text_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw(
        text_skiplinks_back text_skiplinks_forward text_entry_prev text_entry_next text_meta_location
        text_meta_music text_meta_mood text_meta_groups text_edit_entry text_edit_tags text_mem_add text_tell_friend
        text_flag text_permalink
    );
    return $self->_append_props("entry_props", @props);
}

sub comment_props {
    my $self = shift;
    my @props = qw(
        color_comment_bar comment_screened_bgcolor comment_screened_fgcolor text_post_comment
        text_read_comments text_post_comment_friends text_read_comments_friends text_comment_frozen
        text_comment_reply text_comment_parent text_comment_thread
    );
    return $self->_append_props("comment_props", @props);
}


### Themes ###

package LJ::S2Theme::disjointed::blackblu;
use base qw(LJ::S2Theme::disjointed);
sub cats { qw( cool dark modern ) }

package LJ::S2Theme::disjointed::dante;
use base qw(LJ::S2Theme::disjointed);
sub cats { qw( cool dark modern ) }

package LJ::S2Theme::disjointed::greenhues;
use base qw(LJ::S2Theme::disjointed);
sub cats { qw( cool modern nature ) }

package LJ::S2Theme::disjointed::monotonegrey;
use base qw(LJ::S2Theme::disjointed);
sub cats { qw( dark modern ) }

package LJ::S2Theme::disjointed::satinhandshake;
use base qw(LJ::S2Theme::disjointed);
sub cats { qw( warm dark modern ) }

package LJ::S2Theme::disjointed::xcolibur;
use base qw(LJ::S2Theme::disjointed);
sub cats { qw( cool modern featured ) }

1;
