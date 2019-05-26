package LJ::S2Theme::trifecta;
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
    my @props = qw(
        color_main_background
        color_main_text
        color_main_link
        color_main_link_active
        color_main_link_hover
        color_main_link_visited
        color_main_border
        image_background_main_group
    );
    return $self->_append_props( "page_props", @props );
}

sub module_props {
    my $self  = shift;
    my @props = qw(
        color_secondary_background
        color_tertiary_background
        color_module_background_alt
        color_module_text_alt
        color_module_link_alt
        color_module_link_active_alt
        color_module_link_hover_alt
        color_module_link_visited_alt
        color_module_title_background_alt
        color_module_title_alt
        color_module_border_alt
        image_background_secondary_group
        image_background_tertiary_group
        image_background_module_alt_group
    );
    return $self->_append_props( "module_props", @props );
}

sub footer_props {
    my $self  = shift;
    my @props = qw( color_footer_text color_footer_border image_background_footer_group );
    return $self->_append_props( "footer_props", @props );
}

sub archive_props {
    my $self  = shift;
    my @props = qw(
        color_calendar_background
        color_calendar_link
        color_calendar_link_active
        color_calendar_link_hover
        color_calendar_link_visited
        color_calendar_text
        color_calendar_border
    );
    return $self->_append_props( "archive_props", @props );
}

1;
