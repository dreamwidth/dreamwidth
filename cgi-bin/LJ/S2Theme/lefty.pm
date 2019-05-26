package LJ::S2Theme::lefty;
use base qw( LJ::S2Theme );
use strict;

sub layouts {
    (
        "1"  => "one-column",
        "1s" => "one-column-split",
        "2l" => "two-columns-left",
        "2r" => "two-columns-right"
    )
}
sub layout_prop { "layout_type" }

sub module_props {
    my $self  = shift;
    my @props = qw(
        color_module_background_accent
        color_module_titlelist_border
    );
    return $self->_append_props( "module_props", @props );
}

sub page_props {
    my $self  = shift;
    my @props = qw(
        color_page_left_border
        color_page_right_border
        color_page_navigation_link
        color_page_navigation_link_hover
        color_page_navigation_link_active
        color_page_navigation_link_visited
        font_page_navigation
    );
    return $self->_append_props( "page_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw(
        color_headernav_background
        color_headernav_current_background
        color_headernav_hover_background
        color_headernav_text
        color_header_title_background
    );
    return $self->_append_props( "header_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw(
        color_entry_background_accent
        color_entry_titleuserpic_border
        color_entry_footer_text
        font_entry_footer
    );
    return $self->_append_props( "entry_props", @props );
}

sub comment_props {
    my $self  = shift;
    my @props = qw(
        color_comment_footer_text
        font_comment_footer
    );
    return $self->_append_props( "comment_props", @props );
}
1;
