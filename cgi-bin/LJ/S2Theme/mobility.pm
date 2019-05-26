package LJ::S2Theme::mobility;
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

1;

sub display_option_props {
    my $self  = shift;
    my @props = qw(
        content_width
        control_strip_reduced
    );
    return $self->_append_props( "display_option_props", @props );
}

sub module_props {
    my $self  = shift;
    my @props = qw(
        color_module_highlight
    );
    return $self->_append_props( "module_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw(
        color_header_footer_border
    );
    return $self->_append_props( "header_props", @props );
}
