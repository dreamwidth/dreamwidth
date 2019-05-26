package LJ::S2Theme::fantaisie;
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
        color_module_calendar_background
        color_module_calendar_link
        color_module_calendar_shadow
        color_module_calendar_background_active
        color_module_calendar_link_active
        color_module_calendar_shadow_active
        color_module_calendar_background_hover
        color_module_calendar_link_hover
        color_module_calendar_shadow_hover
        color_module_calendar_background_visited
        color_module_calendar_link_visited
        color_module_calendar_shadow_visited
        image_background_module_title_url
        image_background_module_title_height
        image_background_module_title_width
        image_background_module_footer_url
        image_background_module_footer_height
    );
    return $self->_append_props( "module_props", @props );
}

sub navigation_props {
    my $self  = shift;
    my @props = qw(
        image_background_navigation_url
        image_background_navigation_url_alt
        image_background_navigation_height
        image_background_navigation_width
    );
    return $self->_append_props( "navigation_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw(
        color_header_image_border
        color_header_image_shadow
        image_background_header_secondary_url
        image_background_header_secondary_height
        image_background_header_secondary_width
    );
    return $self->_append_props( "header_props", @props );
}

sub footer_props {
    my $self  = shift;
    my @props = qw(
        color_footer_text
        font_journal_footer
        font_journal_footer_size
        font_journal_footer_units
        image_background_footer_url
        image_background_footer_height
        image_background_footer_width
    );
    return $self->_append_props( "footer_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw(
        image_background_entry_title_url
        image_background_entry_title_height
        image_background_entry_title_width
    );
    return $self->_append_props( "entry_props", @props );
}

sub archive_props {
    my $self  = shift;
    my @props = qw( color_calendar_header_background color_calendar_header_text );
    return $self->_append_props( "archive_props", @props );
}

1;
