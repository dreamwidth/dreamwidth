package LJ::S2Theme::leftovers;
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

sub archive_props {
    my $self  = shift;
    my @props = qw(
        color_calendar_header_background
        color_calendar_header_text
        color_calendar_entryday_background
        color_calendar_entryday_text
        color_calendar_entryday_link );
    return $self->_append_props( "archive_props", @props );
}

sub page_props {
    my $self = shift;
    my @props =
        qw(color_calender_header_background color_calender_entryday_background color_userpic_border);
    return $self->_append_props( "page_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw( color_header_border);
    return $self->_append_props( "header_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw( color_entry_title_border);
    return $self->_append_props( "entry_props", @props );
}

sub module_props {
    my $self  = shift;
    my @props = qw( color_module_title_border
        color_navlinks_link
        color_navlinks_recent_background
        color_navlinks_recent_hover_background
        color_navlinks_archive_background
        color_navlinks_archive_hover_background
        color_navlinks_read_background
        color_navlinks_read_hover_background
        color_navlinks_network_background
        color_navlinks_network_hover_background
        color_navlinks_tags_background
        color_navlinks_tags_hover_background
        color_navlinks_memories_background
        color_navlinks_memories_hover_background
        color_navlinks_userinfo_background
        color_navlinks_userinfo_hover_background);
    return $self->_append_props( "module_props", @props );
}

1;
