package LJ::S2Theme::nouveauoleanders;
use base qw( LJ::S2Theme );
use strict;

sub layouts { ( "1" => "one-column", "2l" => "two-columns-left", "2r" => "two-columns-right", "3" => "three-columns-sides", "3r" => "three-columns-right", "3l" => "three-columns-left" ) }
sub layout_prop { "layout_type" }

sub designer { "branchandroot" }

sub entry_props {
    my $self = shift;
    my @props = qw(
        image_entry_border_group
        image_entry_border_url
        image_entry_border_repeat
        image_entry_border_position
        image_entry_border_end_odd_group
        image_entry_border_end_odd_url
        image_entry_border_end_odd_repeat
        image_entry_border_end_odd_position
        image_entry_border_end_even_group
        image_entry_border_end_even_url
        image_entry_border_end_even_repeat
        image_entry_border_end_even_position
    );
    return $self->_append_props( "entry_props", @props );
}

sub comment_props {
    my $self = shift;
    my @props = qw(
        image_comment_border_group
        image_comment_border_url
        image_comment_border_repeat
        image_comment_border_position
        image_comment_border_end_odd_group
        image_comment_border_end_odd_url
        image_comment_border_end_odd_repeat
        image_comment_border_end_odd_position
        image_comment_border_end_even_group
        image_comment_border_end_even_url
        image_comment_border_end_even_repeat
        image_comment_border_end_even_position
    );
    return $self->_append_props( "comment_props", @props );
}

package LJ::S2Theme::nouveauoleanders::dustyantique;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw() }

package LJ::S2Theme::nouveauoleanders::huntergreen;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw() }
sub designer { "dancing_serpent" }

package LJ::S2Theme::nouveauoleanders::nightfall;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw() }
sub designer { "dancing_serpent" }

package LJ::S2Theme::nouveauoleanders::palejewels;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw( featured ) }
sub designer { "dancing_serpent" }

package LJ::S2Theme::nouveauoleanders::peridot;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw( featured ) }
sub designer { "dancing_serpent" }

package LJ::S2Theme::nouveauoleanders::piquant;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw() }

package LJ::S2Theme::nouveauoleanders::seaandsalt;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw() }

package LJ::S2Theme::nouveauoleanders::sienna;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw() }

package LJ::S2Theme::nouveauoleanders::tearose;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw( featured ) }
sub designer { "dancing_serpent" }

package LJ::S2Theme::nouveauoleanders::wisteria;
use base qw( LJ::S2Theme::nouveauoleanders );
sub cats { qw() }

1;
