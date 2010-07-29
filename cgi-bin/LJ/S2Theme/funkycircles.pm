package LJ::S2Theme::funkycircles;
use base qw( LJ::S2Theme );

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "900degrees" }

sub page_props {
    my $self = shift;
    my @props = qw( color_page_title_background color_page_subtitle_background color_page_subtitle );
    return $self->_append_props( "page_props", @props );
}

sub module_props {
    my $self = shift;
    my @props = qw( image_module_list image_module_list_hover image_module_list_active );
    return $self->_append_props( "module_props", @props );
}

sub entry_props {
    my $self = shift;
    my @props = qw(
        color_entry_userpic_border
        color_entry_link_hover_background
        color_entry_poster_border
        color_entry_footer_background
        color_entry_footer_text
        color_entry_footer_link
        color_entry_footer_link_active
        color_entry_footer_link_hover
        color_entry_footer_link_visited
        color_entry_footer_border
        image_entry_list_background_group
        image_entry_list_background_url
        image_entry_list_background_repeat
        image_entry_list_background_position
    );
    return $self->_append_props( "entry_props", @props );
}

package LJ::S2Theme::funkycircles::atomicorange;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw() }

package LJ::S2Theme::funkycircles::chocolaterose;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw( featured ) }

package LJ::S2Theme::funkycircles::darkblue;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw() }

package LJ::S2Theme::funkycircles::darkpurple;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw() }

package LJ::S2Theme::funkycircles::earthygreen;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw() }

package LJ::S2Theme::funkycircles::industrialpink;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw() }

package LJ::S2Theme::funkycircles::industrialteal;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw() }

package LJ::S2Theme::funkycircles::lightondark;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw() }
sub designer { "cesy" }

package LJ::S2Theme::funkycircles::nevermore;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw() }
sub designer { "wizard101" }

package LJ::S2Theme::funkycircles::nnwm2009;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw() }
sub designer { "zvi" }

package LJ::S2Theme::funkycircles::seablues;
use base qw( LJ::S2Theme::funkycircles );
sub cats { qw() }

1;
