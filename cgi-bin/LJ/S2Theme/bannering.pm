package LJ::S2Theme::bannering;
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
        color_navlinks_link_current
    );
    return $self->_append_props( "module_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw(
        color_header_inner_background
        color_navlinks_link
        color_navlinks_link_visited
        color_header_border
        image_header_background_inner_group
        image_background_header_inner_height
    );
    return $self->_append_props( "header_props", @props );
}

1;
