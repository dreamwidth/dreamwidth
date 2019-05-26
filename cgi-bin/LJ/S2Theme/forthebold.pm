package LJ::S2Theme::forthebold;
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
    my @props = qw( color_module_title_border color_module_profile_userpic_border );
    return $self->_append_props( "module_props", @props );
}

sub entry_props {
    my $self  = shift;
    my @props = qw( color_entry_title_border color_entry_userpic_border );
    return $self->_append_props( "entry_props", @props );
}

sub comment_props {
    my $self  = shift;
    my @props = qw( color_comment_title_border color_comment_userpic_border );
    return $self->_append_props( "comment_props", @props );
}

sub archive_props {
    my $self  = shift;
    my @props = qw(
        color_calendar_background
        color_calendar_text
        color_calendar_link
        color_calendar_link_active
        color_calendar_link_hover
        color_calendar_link_visited
    );
    return $self->_append_props( "archive_props", @props );
}

1;
