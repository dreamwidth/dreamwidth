package LJ::S2Theme::patsy;
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
    my @props = qw( color_content_border );
    return $self->_append_props( "page_props", @props );
}

sub archive_props {
    my $self  = shift;
    my @props = qw(
        color_calendar_header_background
        color_calendar_entryday_background
        color_calendar_header_text );
    return $self->_append_props( "archive_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw( color_header_border color_navlinks_current );
    return $self->_append_props( "header_props", @props );
}

sub footer_props {
    my $self  = shift;
    my @props = qw( color_footer_border );
    return $self->_append_props( "footer_props", @props );
}

1;
