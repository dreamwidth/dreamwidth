package LJ::S2Theme::skittlishdreams;
use base qw( LJ::S2Theme );
use strict;

sub layouts { ( "2r" => "two-columns-right", "2l" => "two-columns-left" ) }
sub layout_prop { "layout_type" }

sub page_props {
    my $self = shift;
    my @props = qw(
        image_background_container_group
        image_background_container_url
        image_background_container_repeat
        image_background_container_position
    );
    return $self->_append_props( "page_props", @props );
}

sub navigation_props {
    my $self = shift;
    my @props = qw(
        image_background_navigation_group
        image_background_navigation_url
        image_background_navigation_repeat
        image_background_navigation_position
    );
    return $self->_append_props( "navigation_props", @props );
}

sub footer_props {
    my $self = shift;
    my @props = qw(
        image_background_footer_group
        image_background_footer_url
        image_background_footer_repeat
        image_background_footer_position
    );
    return $self->_append_props( "footer_props", @props );
}

sub entry_props {
    my $self = shift;
    my @props = qw(
        color_entry_title_border
        color_entry_title_border_alt
        color_entry_metadata_text
    );
    return $self->_append_props( "entry_props", @props );
}

1;
