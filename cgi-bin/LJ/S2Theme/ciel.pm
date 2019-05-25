package LJ::S2Theme::ciel;
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
    my $self  = shift;
    my @props = qw( color_page_subtitle );
    return $self->_append_props( "page_props", @props );
}

sub archive_props {
    my $self  = shift;
    my @props = qw( color_calendar_entryday_background );
    return $self->_append_props( "archive_props", @props );
}

sub module_props {
    my $self  = shift;
    my @props = qw(
        font_navlinks
        color_navlinks_link
        color_navlinks_link_active
        color_navlinks_link_hover
        color_navlinks_link_visited
        color_navlinks_link_background
        color_navlinks_link_hover_background
        color_navlinks_link_active_background
        color_navlinks_link_visited_background );
    return $self->_append_props( "module_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw(
        color_management_links_background
        color_interaction_links_background
        color_userpic_border
        color_userpic_border_alt
        color_metadata_labels
        font_management
        font_metadata
        color_management_links
        color_entry_management_links_active
        color_entry_management_links_hover
        color_entry_management_links_visited
        color_entry_interaction_links_active
        color_entry_interaction_links_hover
        color_entry_interaction_links_visited
    );
    return $self->_append_props( "entry_props", @props );
}

1;
