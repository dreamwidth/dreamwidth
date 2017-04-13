package LJ::S2Theme::venture;
use base qw( LJ::S2Theme );
use strict;
 
sub layouts { ( "1" => "one-column", "1s" => "one-column-split", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub display_option_props {
    my $self = shift; 
    my @props = qw(
        link_display_topnav
        margins_between_size
        margins_between_unit
        modules_layout_mode
        font_display_allcaps
    );
    return $self->_append_props( "display_option_props", @props );
}

sub header_props {
    my $self = shift; 
    my @props = qw(
        color_header_navigation_background 
        color_header_navigation_link_background 
        color_header_navigation_link_background_current 
        color_header_navigation_link 
        color_header_navigation_link_current 
        color_header_navigation_link_active 
        color_header_navigation_link_hover 
        color_header_navigation_link_visited
        color_page_header_gradient
        color_page_subtitle
        color_page_pagetitle
        font_header_navigation
        font_header_navigation_size
        font_header_navigation_units
        font_journal_pagetitle
        font_journal_pagetitle_size
        font_journal_pagetitle_units
        image_background_header_navigation_group
        image_background_header_navigation_url
        image_background_header_navigation_repeat
        image_background_header_navigation_position
        image_background_header_navigation_link_group
        image_background_header_navigation_link_url
        image_background_header_navigation_link_repeat
        image_background_header_navigation_link_position
        image_background_header_navigation_link_current_group
        image_background_header_navigation_link_current_url
        image_background_header_navigation_link_current_repeat
        image_background_header_navigation_link_current_position
    );
    return $self->_append_props( "header_props", @props );
}

sub entry_props {
    my $self = shift; 
    my @props = qw(
        color_entry_title_rightborder 
        color_entry_datetime_background 
        color_entry_datetime_sub_background 
        color_entry_datetime_text 
        color_entry_datetime_link 
        color_entry_datetime_link_active
        color_entry_datetime_link_hover 
        color_entry_datetime_link_visited 
        color_entry_metadata 
        color_entry_quote_background 
        color_entry_quote_border 
        color_entry_quote_text 
        color_entry_userpic_background
        color_entry_userpic_border 
        font_entry_text
        font_entry_text
        font_entry_text_units
        font_entry_datetime
        font_entry_datetime_size
        font_entry_datetime_units
        font_entry_metadata
        font_entry_metadata_size
        font_entry_metadata_units
        font_entry_tags
        font_entry_tags_size
        font_entry_tags_units
        font_entry_manageinteract
        font_entry_manageinteract_size
        font_entry_manageinteract_units
        image_background_entry_title_group
        image_background_entry_title_url
        image_background_entry_title_repeat
        image_background_entry_title_position
        image_background_entry_datetime_group
        image_background_entry_datetime_url
        image_background_entry_datetime_repeat
        image_background_entry_datetime_position
        image_background_entry_datetime_sub_group
        image_background_entry_datetime_sub_url
        image_background_entry_datetime_sub_repeat
        image_background_entry_datetime_sub_position
    );
    return $self->_append_props( "entry_props", @props );
}

sub module_props {
    my $self = shift; 
    my @props = qw(
        color_module_title_rightborder 
        color_module_title_link 
        color_module_title_link_active 
        color_module_title_link_hover
        color_module_title_link_visited 
        color_module_link_alt 
        color_module_link_alt_active 
        color_module_link_alt_hover
        color_module_link_alt_visited 
        color_module_list_border 
        color_module_navigation_background 
        color_module_navigation_background_current 
        color_module_navigation_link 
        color_module_navigation_link_current 
        color_module_navigation_link_active 
        color_module_navigation_link_hover 
        color_module_navigation_link_visited
        font_module_navigation
        font_module_navigation_size
        font_module_navigation_units
        font_module_customtext
        font_module_customtext_size
        font_module_customtext_units
        image_background_module_title_group
        image_background_module_title_url
        image_background_module_title_repeat
        image_background_module_title_position
        module_headernavigation_group
    );
    return $self->_append_props( "module_props", @props );
}

sub archive_props {
    my $self = shift; 
    my @props = qw(
        color_calendar_background
        color_calendar_foreground
    );
    return $self->_append_props( "archive_props", @props );
}

1;


