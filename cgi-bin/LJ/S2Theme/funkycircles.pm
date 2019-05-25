package LJ::S2Theme::funkycircles;
use base qw( LJ::S2Theme );
use strict;

sub layouts {
    (
        "1"  => "one-column",
        "1s" => "one-column-split",
        "2l" => "two-columns-left",
        "2r" => "two-columns-right",
        "3"  => "three-columns-sides",
        "3r" => "three-columns-right",
        "3l" => "three-columns-left"
    )
}
sub layout_prop { "layout_type" }

sub page_props {
    my $self = shift;
    my @props =
        qw( color_page_title_background color_page_subtitle_background color_page_subtitle );
    return $self->_append_props( "page_props", @props );
}

sub module_props {
    my $self  = shift;
    my @props = qw(
        image_module_list
        image_module_list_active
        image_module_list_hover
        color_specificmodule_background
        color_specificmodule_background_alt
        color_specificmodule_background_hover
        color_specificmodule_background_visited
        color_specificmodule_text
        color_specificmodule_text_alt
        color_specificmodule_text_hover
        color_specificmodule_text_visited
    );
    return $self->_append_props( "module_props", @props );
}

sub entry_props {
    my $self  = shift;
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

1;
