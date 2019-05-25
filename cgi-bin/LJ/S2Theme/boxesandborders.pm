package LJ::S2Theme::boxesandborders;
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

sub header_props {
    my $self  = shift;
    my @props = qw( color_header_link_hover_background );
    return $self->_append_props( "header_props", @props );
}

1;
