package LJ::S2Theme::librariansdream;
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
    my $self = shift;
    my @props =
        qw( color_module_link_background color_module_link_hover_background color_module_link_border color_module_link_hover_border  color_sidebars_background );
    return $self->_append_props( "module_props", @props );
}

sub navigation_props {
    my $self = shift;
    my @props =
        qw( color_navigation_link color_navigation_link_visited color_navigation_link_active color_navigation_link_hover);
    return $self->_append_props( "navigation_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw( color_entry_management_background color_primary_background  );
    return $self->_append_props( "entry_props", @props );
}

1;
