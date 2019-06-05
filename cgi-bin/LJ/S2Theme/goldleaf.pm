package LJ::S2Theme::goldleaf;
use base qw( LJ::S2Theme );
use strict;

sub layouts     { ( "1s" => "one-column-split" ) }
sub layout_prop { "layout_type" }

sub page_props {
    my $self  = shift;
    my @props = qw( c
        topnav_show
        page_top_image
        color_canvas_background
        color_topbar_background
        color_bottombar_background
        color_topbar_border_top
        color_topbar_border_bottom
        color_bottombar_border_top
        font_journal_pagetitle
        font_journal_pagetitle_size
        font_journal_pagetitle_units
        image_background_canvas_group
        image_background_canvas_url
        image_background_canvas_repeat
        image_background_canvas_position
        image_background_topbar_group
        image_background_topbar_url
        image_background_topbar_repeat
        image_background_topbar_position
        image_background_bottombar_group
        image_background_bottombar_url
        image_background_bottombar_repeat
        image_background_bottombar_position
        image_page_top
        primary_width_size
        primary_width_units
        topbar_width_size
        topbar_width_units
        bottombar_width_size
        bottombar_width_units
    );
    return $self->_append_props( "page_props", @props );
}

sub module_props {
    my $self  = shift;
    my @props = qw(
        color_module_tag_link
        color_module_tag_link_visited
        color_module_tag_link_hover
        color_module_tag_link_active
        font_module_management
        font_module_management_size
        font_module_management_units
        font_navigation
        font_navigation_size
        font_navigation_units
        font_linkslist
        font_linkslist_size
        font_linkslist_units
        image_module_list_bullet
    );
    return $self->_append_props( "module_props", @props );
}

sub footer_props {
    my $self  = shift;
    my @props = qw(
        image_background_footer_group
        image_background_footer_url
        image_background_footer_repeat
        image_background_footer_position
    );
    return $self->_append_props( "footer_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw(
        entry_comment_text_align
        metadata_label_images
        color_entry_shadow
        color_entry_datetime_text
        color_metadata_text
        font_entry_datetime
        font_entry_datetime_size
        font_entry_datetime_units
        font_entry_management
        font_entry_management_size
        font_entry_management_units
        image_background_entry_header_group
        image_background_entry_header_url
        image_background_entry_header_repeat
        image_background_entry_header_position
        image_metadata_mood
        image_metadata_location
        image_metadata_music
        image_metadata_groups
        image_metadata_xpost
        image_list_bullet
    );
    return $self->_append_props( "entry_props", @props );
}

sub comment_props {
    my $self  = shift;
    my @props = qw(
        image_background_comment_header_group
        image_background_comment_header_url
        image_background_comment_header_repeat
        image_background_comment_header_position
    );
    return $self->_append_props( "comment_props", @props );
}

1;
