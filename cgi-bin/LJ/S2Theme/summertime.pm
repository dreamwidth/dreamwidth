package LJ::S2Theme::summertime;
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
        color_module_background_shadow
        color_module_top_background
        color_module_top_text
        color_module_top_link
        color_module_top_link_active
        color_module_top_link_hover
        color_module_top_link_visited
        color_module_top_title_background
        color_module_top_title
        color_module_top_border
        color_module_top_background_shadow
        color_module_bottom_background
        color_module_bottom_text
        color_module_bottom_link
        color_module_bottom_link_active
        color_module_bottom_link_hover
        color_module_bottom_link_visited
        color_module_bottom_title_background
        color_module_bottom_title
        color_module_bottom_border
        color_module_bottom_background_shadow
    );
    return $self->_append_props( "module_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw(
        color_header_background_shadow
        color_page_title_shadow
        color_header_icons_background
        color_header_icons_background_alt
        color_header_icons_shadow
        image_recent
        image_recent_alt
        image_archive
        image_archive_alt
        image_reading
        image_reading_alt
        image_network
        image_network_alt
        image_tags
        image_tags_alt
        image_memories
        image_memories_alt
        image_profile
        image_profile_alt
    );
    return $self->_append_props( "header_props", @props );
}

sub footer_props {
    my $self  = shift;
    my @props = qw(
        color_footer_link_shadow
        color_footer_icon_background
        color_footer_icon_shadow
        color_footer_background_shadow
        font_journal_footer
        font_journal_footer_size
        font_journal_footer_units
        image_poweredby
    );
    return $self->_append_props( "footer_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw( color_entry_background_shadow );
    return $self->_append_props( "entry_props", @props );
}

1;
