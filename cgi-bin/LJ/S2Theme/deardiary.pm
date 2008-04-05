package LJ::S2Theme::deardiary;
use base qw(LJ::S2Theme);

sub layouts { ( "2l" => 1 ) }
sub cats { qw( warm illustrated modern pattern ) }
sub designer { "Martin Atkins" }

sub display_option_props {
    my $self = shift;
    my @props = qw( title_pattern );
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
    my @props = qw( clr_title_bg clr_title_fg clr_title_pattern clr_title_separator );
    return $self->_append_props("title_props", @props);
}

sub sidebar_props {
    my $self = shift;
    my @props = qw( clr_sidebar_bg clr_sidebar_fg );
    return $self->_append_props("sidebar_props", @props);
}

sub comment_props {
    my $self = shift;
    my @props = qw( text_post_comment text_read_comments text_post_comment_friends text_read_comments_friends );
    return $self->_append_props("comment_props", @props);
}


### Themes ###

package LJ::S2Theme::deardiary::cellular;
use base qw(LJ::S2Theme::deardiary);
sub cats { qw( cool illustrated modern pattern ) }

package LJ::S2Theme::deardiary::nature;
use base qw(LJ::S2Theme::deardiary);
sub cats { qw( cool illustrated modern nature pattern ) }

package LJ::S2Theme::deardiary::redrock;
use base qw(LJ::S2Theme::deardiary);
sub cats { qw( warm dark illustrated modern pattern ) }

package LJ::S2Theme::deardiary::regal;
use base qw(LJ::S2Theme::deardiary);
sub cats { qw( cool dark illustrated modern pattern ) }

package LJ::S2Theme::deardiary::royalty;
use base qw(LJ::S2Theme::deardiary);
sub cats { qw( cool illustrated modern ) }

package LJ::S2Theme::deardiary::striking;
use base qw(LJ::S2Theme::deardiary);
sub cats { qw( dark illustrated modern pattern tech ) }

package LJ::S2Theme::deardiary::unsaturates;
use base qw(LJ::S2Theme::deardiary);
sub cats { qw( illustrated modern pattern ) }

package LJ::S2Theme::deardiary::wired;
use base qw(LJ::S2Theme::deardiary);
sub cats { qw( cool illustrated modern pattern tech ) }

1;
