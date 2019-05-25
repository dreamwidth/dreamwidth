package LJ::S2Theme::marginless;
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
    my @props = qw( color_userpic_background );
    return $self->_append_props( "page_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw( color_header_link_current );
    return $self->_append_props( "header_props", @props );
}

sub archive_props {
    my $self  = shift;
    my @props = qw( color_calendar_background color_calendar_entry );
    return $self->_append_props( "archive_props", @props );
}

sub comment_props {
    my $self  = shift;
    my @props = qw( color_comment_title_even color_comment_title_background_even );
    return $self->_append_props( "comment_props", @props );
}

1;
