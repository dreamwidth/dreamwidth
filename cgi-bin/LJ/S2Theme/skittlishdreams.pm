package LJ::S2Theme::skittlishdreams;
use base qw( LJ::S2Theme );

sub layouts { ( "2r" => "two-columns-right", "2l" => "two-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "Kaigou" }

sub page_props {
    my $self = shift;
    my @props = qw( color_page_details_text );
    return $self->_append_props( "page_props", @props );
}

sub entry_props {
    my $self = shift;
    my @props = qw( color_entry_title_border color_entry_title_border_alt color_entry_metadata_text );
    return $self->_append_props( "entry_props", @props );
}


package LJ::S2Theme::skittlishdreams::blue;
use base qw( LJ::S2Theme::skittlishdreams );
sub cats { qw() }

package LJ::S2Theme::skittlishdreams::cyan;
use base qw( LJ::S2Theme::skittlishdreams );
sub cats { qw() }

package LJ::S2Theme::skittlishdreams::green;
use base qw( LJ::S2Theme::skittlishdreams );
sub cats { qw() }

package LJ::S2Theme::skittlishdreams::orange;
use base qw( LJ::S2Theme::skittlishdreams );
sub cats { qw( base featured ) }

package LJ::S2Theme::skittlishdreams::pink;
use base qw( LJ::S2Theme::skittlishdreams );
sub cats { qw() }

package LJ::S2Theme::skittlishdreams::red;
use base qw( LJ::S2Theme::skittlishdreams );
sub cats { qw() }

package LJ::S2Theme::skittlishdreams::violet;
use base qw( LJ::S2Theme::skittlishdreams );
sub cats { qw() }

1;

