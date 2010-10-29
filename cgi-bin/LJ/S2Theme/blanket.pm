package LJ::S2Theme::blanket;
use base qw( LJ::S2Theme );
use strict;

sub layouts { ( "1" => "one-column" ) }
sub layout_prop { "layout_type" }

sub header_props {
    my $self = shift;
    my @props = qw( color_header_footer_border );
    return $self->_append_props( "header_props", @props );
}

1;
