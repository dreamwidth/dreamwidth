package LJ::S2Theme::refriedtablet;
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
        font_view_text
        font_view_text_size
        font_view_text_units
    );
    return $self->_append_props( "header_props", @props );
}

sub comment_props {
    my $self  = shift;
    my @props = qw(
        font_comment_special
        font_comment_special_size
        font_comment_special_units
    );
    return $self->_append_props( "comment_props", @props );
}

1;
