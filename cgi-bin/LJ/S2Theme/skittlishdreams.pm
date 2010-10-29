package LJ::S2Theme::skittlishdreams;
use base qw( LJ::S2Theme );
use strict;

sub layouts { ( "2r" => "two-columns-right", "2l" => "two-columns-left" ) }
sub layout_prop { "layout_type" }

sub entry_props {
    my $self = shift;
    my @props = qw( color_entry_title_border color_entry_title_border_alt color_entry_metadata_text );
    return $self->_append_props( "entry_props", @props );
}

1;
