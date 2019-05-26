package LJ::S2Theme::abstractia;
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

sub page_props {
    my $self  = shift;
    my @props = qw(
        image_background_content_header_group
        image_background_content_group
        image_background_content_footer_group
        image_background_userpic_group
        image_background_sidebar_group
        image_background_archive_calendar_group
        image_background_calendar_and_form_group
        color_content_header_background
        color_content_background
        color_content_footer_background
        color_userpic_background
        color_sidebar_background
        color_archive_calendar_background
        color_calendar_and_form_background
    );
    return $self->_append_props( "page_props", @props );
}

1;

