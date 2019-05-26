package LJ::S2Theme::headsup;
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
        color_module_title_border
    );
    return $self->_append_props( "module_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw(
        image_foreground_header_url
        int image_foreground_header_height
        string image_foreground_header_alignment
        image_foreground_header_position
        image_foreground_header_alt
    );
    return $self->_append_props( "header_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw(
        color_entry_title_border
        color_userpic_background
    );
    return $self->_append_props( "entry_props", @props );
}

sub comment_props {
    my $self  = shift;
    my @props = qw(
        color_comment_title_even
        color_comment_title_background_even
        color_comment_title_border
    );
    return $self->_append_props( "comment_props", @props );
}
1;
