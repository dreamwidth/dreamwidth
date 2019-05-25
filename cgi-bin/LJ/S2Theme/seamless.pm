package LJ::S2Theme::seamless;
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
        color_module_calendar_header_background
        color_module_calendar_header
        color_module_calendar_entry
    );
    return $self->_append_props( "module_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw(
        color_metadata_label
        color_metadata_text
        font_interaction_links
        font_interaction_links_size
        font_interaction_links_units
    );
    return $self->_append_props( "entry_props", @props );
}

sub archive_props {
    my $self  = shift;
    my @props = qw(
        color_calendar_header_background
        color_calendar_header
        color_calendar_entry
    );
    return $self->_append_props( "archive_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw( color_page_subtitle );
    return $self->_append_props( "header_props", @props );
}

1;
