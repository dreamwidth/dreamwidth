package LJ::S2Theme::planetcaravan;
use base qw( LJ::S2Theme );
use strict;

sub layouts { ( "1" => "one-column", "1s" => "one-column-split", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub module_props {
    my $self = shift;
    my @props = qw(
        color_navlinks_current
    );
    return $self->_append_props( "module_props", @props );
}

sub entry_props {
    my $self = shift;
    my @props = qw(
    color_entry_interaction_links
    color_entry_interaction_links_active
    color_entry_interaction_links_hover
    color_entry_interaction_links_visited
    color_entry_footer_background
    color_entry_footer_text
    color_alternate_entry_border
    color_alternate2_entry_border
    color_alternate3_entry_border
    );
    return $self->_append_props( "entry_props", @props );
}

sub page_props {
    my $self = shift;
    my @props = qw(
    color_journal_subtitle
    color_userpic_border
    );
    return $self->_append_props( "page_props", @props );
}


1;
