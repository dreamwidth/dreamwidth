package LJ::S2Theme::refriedpaper;
use base qw(LJ::S2Theme);

sub layouts { ( "2l" => "left", "2r" => "right" ) }
sub layout_prop { "sidebar_position" }
sub cats { qw( clean warm modern featured ) }
sub designer { "idigital" }

sub display_option_props {
    my $self = shift;
    my @props = qw( show_calendar );
    return $self->_append_props("display_option_props", @props);
}

sub navigation_props {
    my $self = shift;
    my @props = qw(
        text_view_recent text_view_friends text_view_friends_comm text_view_archive text_view_userinfo
        text_left_comments text_comment_divider text_right_comments
    );
    return $self->_append_props("navigation_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( page_fgcolor page_link page_alink page_hlink page_vlink );
    return $self->_append_props("text_props", @props);
}

sub sidebar_props {
    my $self = shift;
    my @props = qw( subhead_bgcolor subhead_fgcolor );
    return $self->_append_props("sidebar_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw(
        border_color_entries date_fgcolor text_skiplinks_back text_skiplinks_forward text_entry_prev text_entry_next
        text_security text_meta_location text_meta_music text_meta_mood text_meta_groups text_edit_entry text_edit_tags text_mem_add
        text_tell_friend text_flag text_permalink
    );
    return $self->_append_props("entry_props", @props);
}

sub comment_props {
    my $self = shift;
    my @props = qw(
        comment_screened_bgcolor comment_screened_fgcolor text_user text_date text_subject text_post_comment text_read_comments
        text_post_comment_friends text_read_comments_friends text_comment_frozen text_comment_reply text_comment_parent text_comment_thread
    );
    return $self->_append_props("comment_props", @props);
}

1;
