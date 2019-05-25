package LJ::S2Theme::wideopen;
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
    my @props = qw(
        color_page_title_textshadow
        color_page_subtitle
        color_header_border
    );
    return $self->_append_props( "header_props", @props );
}

sub footer_props {
    my $self  = shift;
    my @props = qw(
        color_footer_text
        color_footer_border
        image_background_footer_group
        image_background_footer_repeat
        image_background_footer_position
        image_background_footer_height
    );
    return $self->_append_props( "footer_props", @props );
}

sub module_props {
    my $self  = shift;
    my @props = qw(
        color_module_title_textshadow
        color_module_title_border
        color_module_navigation_border
    );
    return $self->_append_props( "module_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw(
        color_entry_title_hover
        color_entry_title_textshadow
        color_entry_userpic_border
    );
    return $self->_append_props( "entry_props", @props );
}

sub comment_props {
    my $self  = shift;
    my @props = qw(
        color_comment_border
        color_comment_title_hover
        color_comment_userpic_border
    );
    return $self->_append_props( "comment_props", @props );
}

1;
