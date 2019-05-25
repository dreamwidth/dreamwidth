package LJ::S2Theme::strata;
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
        color_module_title_link
        color_module_title_link_active
        color_module_title_link_hover
        color_module_title_link_visited
        color_module_footer_background
    );
    return $self->_append_props( "module_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw(
        color_entry_title_link
        color_entry_title_link_active
        color_entry_title_link_hover
        color_entry_title_link_visited
        color_entry_footer_background
    );
    return $self->_append_props( "entry_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw(
        color_header_navlinks_background
        color_header_navlinks_current_background
        color_navlinks_current
        color_navlinks_link
        color_navlinks_link_active
        color_navlinks_link_hover
        color_navlinks_link_visited
    );
    return $self->_append_props( "header_props", @props );
}

1;
