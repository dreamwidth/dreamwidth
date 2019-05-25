package LJ::S2Theme::fiveam;
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
        color_page_usernames
        color_page_usernames_active
        color_page_usernames_hover
        color_page_usernames_visited
    );
    return $self->_append_props( "page_props", @props );
}

sub module_props {
    my $self  = shift;
    my @props = qw( color_module_accent );
    return $self->_append_props( "module_props", @props );
}

sub header_props {
    my $self  = shift;
    my @props = qw( color_header_border color_header_accent );
    return $self->_append_props( "header_props", @props );
}

sub footer_props {
    my $self  = shift;
    my @props = qw( color_footer_border );
    return $self->_append_props( "footer_props", @props );
}

sub comment_props {
    my $self  = shift;
    my @props = qw( color_comment_interaction_links color_comment_interaction_links_border );
    return $self->_append_props( "comment_props", @props );
}

1;
