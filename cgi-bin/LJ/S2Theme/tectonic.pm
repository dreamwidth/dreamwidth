package LJ::S2Theme::tectonic;
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

sub module_props {
    my $self  = shift;
    my @props = qw(
        color_module_list_border
        color_module_list_background_hover
        color_module_calendar_background
        color_module_calendar_text
        color_module_calendar_link
        color_module_calendar_link_hover
        color_module_calendar_link_visited
        color_module_calendar_link_active
    );
    return $self->_append_props( "module_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw(
        color_header_links
        color_header_links_hover
        color_header_links_active
        color_header_links_visited
        color_header_links_background
        color_header_links_border
        color_header_links_border_hover
    );
    return $self->_append_props( "header_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw(
        color_entry_interaction_links_hover
        color_entry_interaction_links_active
        color_entry_interaction_links_visited
        color_entry_footer_background
        color_entry_interaction_links_background
        color_entry_interaction_links_background_hover
        color_entry_interaction_links_background_active
        color_entry_interaction_links_background_visited
    );
    return $self->_append_props( "entry_props", @props );
}

sub page_props {
    my $self  = shift;
    my @props = qw(
        color_userpic_border
    );
    return $self->_append_props( "page_props", @props );
}

sub archive_props {
    my $self  = shift;
    my @props = qw(
        color_calendar_background
        color_calendar_text
        color_calendar_link
        color_calendar_link_hover
        color_calendar_link_active
        color_calendar_link_visited
    );
    return $self->_append_props( "archive_props", @props );
}

1;
