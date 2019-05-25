package LJ::S2Theme::pattern;
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

sub footer_props {
    my $self  = shift;
    my @props = qw( color_footer_text );
    return $self->_append_props( "footer_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw(
        image_background_subject_url
        image_background_subject_height
        image_background_subject_width
        image_background_tags_url
        image_background_tags_height
        image_background_tags_width
    );
    return $self->_append_props( "entry_props", @props );
}

1;
