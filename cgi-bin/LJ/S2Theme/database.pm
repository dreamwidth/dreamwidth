package LJ::S2Theme::database;
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
    my @props = qw( color_elements_border color_userpic_shadow );
    return $self->_append_props( "page_props", @props );
}

sub module_props {
    my $self  = shift;
    my @props = qw(
        color_module_title_shadow
        color_module_header_background
        color_module_header_link
        color_module_header_background_active
        color_module_header_link_active
        color_module_header_background_hover
        color_module_header_link_hover
        color_module_header_background_visited
        color_module_header_link_visited
        color_module_header_border
        color_module_calendar_header_background
        color_module_calendar_header_text
        color_module_calendar_background
        color_module_calendar_link
        color_module_calendar_background_active
        color_module_calendar_link_active
        color_module_calendar_background_hover
        color_module_calendar_link_hover
        color_module_calendar_background_visited
        color_module_calendar_link_visited
    );
    return $self->_append_props( "module_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw( color_page_title_shadow );
    return $self->_append_props( "header_props", @props );
}

sub footer_props {
    my $self  = shift;
    my @props = qw(
        image_background_footer_group
        image_background_footer_url
        image_background_footer_repeat
        image_background_footer_position
        image_background_footer_height
    );
    return $self->_append_props( "footer_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw( color_entry_title_shadow );
    return $self->_append_props( "entry_props", @props );
}

sub comment_props {
    my $self  = shift;
    my @props = qw( color_comment_title_shadow );
    return $self->_append_props( "comment_props", @props );
}

sub archive_props {
    my $self  = shift;
    my @props = qw(
        color_calendar_header_background
        color_calendar_header_text
        color_calendar_background
        color_calendar_link
        color_calendar_background_active
        color_calendar_link_active
        color_calendar_background_hover
        color_calendar_link_hover
        color_calendar_background_visited
        color_calendar_link_visited
    );
    return $self->_append_props( "archive_props", @props );
}

1;
