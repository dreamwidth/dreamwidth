package LJ::S2Theme::motion;
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
        color_link_background
        color_link_hover_background
        color_icon_background
        image_link_hover_background_group
        image_link_background_group
        image_icon_background_group
    );
    return $self->_append_props( "page_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw(
        color_entry_footer
        image_entry_footer_group
        image_entry_header_group
    );
    return $self->_append_props( "entry_props", @props );
}

sub module_props {
    my $self  = shift;
    my @props = qw(
        image_module_header_group
    );
    return $self->_append_props( "module_props", @props );
}
1;
