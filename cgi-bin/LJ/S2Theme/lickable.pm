package LJ::S2Theme::lickable;
use base qw(LJ::S2Theme);

sub layouts { ( "2r" => 1 ) }
sub cats { qw( cool illustrated modern ) }
sub designer { "Martin Atkins" }

sub display_option_props {
    my $self = shift;
    my @props = qw( content_width );
    return $self->_append_props("display_option_props", @props);
}

sub navigation_props {
    my $self = shift;
    my @props = qw( text_view_recent text_view_archive text_view_friends text_view_userinfo );
    return $self->_append_props("navigation_props", @props);
}

sub text_props {
    my $self = shift;
    my @props = qw( clr_link_normal clr_link_visited );
    return $self->_append_props("text_props", @props);
}

sub title_props {
    my $self = shift;
    my @props = qw( clr_title_bg clr_title_fg clr_title_pattern clr_title_separator font_title );
    return $self->_append_props("title_props", @props);
}

sub entry_props {
    my $self = shift;
    my @props = qw( clr_page_bg clr_page_fg );
    return $self->_append_props("entry_props", @props);
}

sub comment_props {
    my $self = shift;
    my @props = qw( text_post_comment text_read_comments text_post_comment_friends text_read_comments_friends );
    return $self->_append_props("comment_props", @props);
}


### Themes ###

package LJ::S2Theme::lickable::nature;
use base qw(LJ::S2Theme::lickable);
sub cats { qw( warm illustrated modern nature ) }

package LJ::S2Theme::lickable::steel;
use base qw(LJ::S2Theme::lickable);
sub cats { qw( cool illustrated modern tech ) }

package LJ::S2Theme::lickable::future;
use base qw(LJ::S2Theme::lickable);
sub cats { qw( cool illustrated modern tech ) }

package LJ::S2Theme::lickable::slinkypink;
use base qw(LJ::S2Theme::lickable);
sub cats { qw( warm illustrated modern ) }

1;
